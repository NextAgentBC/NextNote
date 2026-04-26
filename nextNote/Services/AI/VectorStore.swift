import Foundation
import PostgresNIO
import NIOPosix
import Logging

enum ContentTypeFilter: String {
    case epub, pdf, markdown
}

struct ChunkResult {
    let documentID: UUID
    let chunkIndex: Int
    let content: String
    let documentTitle: String?
    let documentAuthor: String?
}

actor VectorStore {
    private let config: PostgresConnection.Configuration
    private let elg: MultiThreadedEventLoopGroup
    private let logger: Logger

    init(dsn: String) {
        // Parse DSN into components.
        // Use defaults — if parse fails, all queries will fail gracefully.
        var host = "localhost"
        var port = 5432
        var user = "postgres"
        var password: String? = nil
        var database = "postgres"

        if let url = URL(string: dsn) {
            host = url.host ?? host
            port = url.port ?? port
            user = url.user ?? user
            password = url.password
            let path = url.path
            if !path.isEmpty {
                database = String(path.dropFirst()) // drop leading "/"
            }
        }

        self.config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: user,
            password: password,
            database: database,
            tls: .disable
        )
        self.elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        var log = Logger(label: "VectorStore")
        log.logLevel = .warning
        self.logger = log
    }

    deinit {
        try? elg.syncShutdownGracefully()
    }

    // MARK: - Connection helper

    private func withConnection<T>(_ body: (PostgresConnection) async throws -> T) async throws -> T {
        let conn = try await PostgresConnection.connect(
            on: elg.any(),
            configuration: config,
            id: Int.random(in: 1...Int.max),
            logger: logger
        )
        defer { Task { try? await conn.close() } }
        return try await body(conn)
    }

    // MARK: - Upsert Document

    func upsertDocument(snapshot: BookSnapshot) async throws -> UUID {
        let hash = snapshot.contentHash
        let contentType = snapshot.contentType
        let title = snapshot.title
        let author = snapshot.author ?? ""
        let sourcePath = snapshot.relativePath

        return try await withConnection { conn in
            // Dedup by content hash in metadata->>'content_hash'
            let rows = try await conn.query(
                "SELECT id FROM documents WHERE metadata->>'content_hash' = \(hash) AND content_type = \(contentType)",
                logger: self.logger
            )
            var existingID: UUID? = nil
            for try await row in rows {
                existingID = try row.decode(UUID.self, context: .default)
                break
            }

            if let id = existingID {
                try await conn.query(
                    "UPDATE documents SET title = \(title), author = \(author), source_path = \(sourcePath) WHERE id = \(id)",
                    logger: self.logger
                )
                return id
            }

            let newID = UUID()
            let metadataJSON = "{\"content_hash\":\"\(hash)\",\"app\":\"nextnote\"}"
            try await conn.query(
                """
                INSERT INTO documents (id, title, author, source_path, content_type, metadata)
                VALUES (\(newID), \(title), \(author), \(sourcePath), \(contentType), \(metadataJSON)::jsonb)
                """,
                logger: self.logger
            )
            return newID
        }
    }

    // MARK: - Insert Chunks

    func insertChunks(
        documentID: UUID,
        chunks: [(idx: Int, content: String, embedding: [Float], tokenCount: Int)]
    ) async throws {
        try await withConnection { conn in
            try await conn.query(
                "DELETE FROM chunks WHERE document_id = \(documentID)",
                logger: self.logger
            )
            for chunk in chunks {
                try await Self.insertOne(conn: conn, documentID: documentID, chunk: chunk, logger: self.logger)
            }
        }
    }

    /// Append one chunk without DELETE — caller is responsible for clearing
    /// previous rows if the embedding session restarts.
    func appendChunk(
        documentID: UUID,
        idx: Int,
        content: String,
        embedding: [Float],
        tokenCount: Int
    ) async throws {
        try await withConnection { conn in
            try await Self.insertOne(
                conn: conn,
                documentID: documentID,
                chunk: (idx: idx, content: content, embedding: embedding, tokenCount: tokenCount),
                logger: self.logger
            )
        }
    }

    func clearChunks(documentID: UUID) async throws {
        try await withConnection { conn in
            try await conn.query(
                "DELETE FROM chunks WHERE document_id = \(documentID)",
                logger: self.logger
            )
        }
    }

    private static func insertOne(
        conn: PostgresConnection,
        documentID: UUID,
        chunk: (idx: Int, content: String, embedding: [Float], tokenCount: Int),
        logger: Logger
    ) async throws {
        let vecString = "[" + chunk.embedding.map { String($0) }.joined(separator: ",") + "]"
        let vecSQL: PostgresQuery = """
            INSERT INTO chunks (document_id, chunk_index, content, embedding, token_count)
            VALUES (\(documentID), \(chunk.idx), \(chunk.content), \(vecString)::vector, \(chunk.tokenCount))
            ON CONFLICT (document_id, chunk_index) DO UPDATE
              SET content = EXCLUDED.content,
                  embedding = EXCLUDED.embedding,
                  token_count = EXCLUDED.token_count
            """
        try await conn.query(vecSQL, logger: logger)
    }

    // MARK: - Search Similar

    func searchSimilar(
        queryEmbedding: [Float],
        k: Int = 10,
        filter: ContentTypeFilter? = nil
    ) async throws -> [(chunk: ChunkResult, similarity: Float)] {
        guard !queryEmbedding.isEmpty else { return [] }
        let vecString = "[" + queryEmbedding.map { String($0) }.joined(separator: ",") + "]"

        return try await withConnection { conn in
            var results: [(chunk: ChunkResult, similarity: Float)] = []

            let query: PostgresQuery
            if let filter {
                let ct = filter.rawValue
                query = """
                    SELECT c.document_id, c.chunk_index, c.content,
                           d.title, d.author,
                           (1.0 - (c.embedding <=> \(vecString)::vector))::float4 AS similarity
                    FROM chunks c
                    JOIN documents d ON d.id = c.document_id
                    WHERE d.content_type = \(ct)
                    ORDER BY c.embedding <=> \(vecString)::vector
                    LIMIT \(k)
                    """
            } else {
                query = """
                    SELECT c.document_id, c.chunk_index, c.content,
                           d.title, d.author,
                           (1.0 - (c.embedding <=> \(vecString)::vector))::float4 AS similarity
                    FROM chunks c
                    JOIN documents d ON d.id = c.document_id
                    ORDER BY c.embedding <=> \(vecString)::vector
                    LIMIT \(k)
                    """
            }

            let rows = try await conn.query(query, logger: self.logger)
            for try await row in rows {
                let (docID, chunkIdx, content, title, author, sim) = try row.decode(
                    (UUID, Int32, String, String, String?, Float).self,
                    context: .default
                )
                let chunk = ChunkResult(
                    documentID: docID,
                    chunkIndex: Int(chunkIdx),
                    content: content,
                    documentTitle: title,
                    documentAuthor: author
                )
                results.append((chunk: chunk, similarity: sim))
            }
            return results
        }
    }

    // MARK: - Delete Document

    func deleteDocument(_ documentID: UUID) async throws {
        try await withConnection { conn in
            // ON DELETE CASCADE handles chunks
            try await conn.query(
                "DELETE FROM documents WHERE id = \(documentID)",
                logger: self.logger
            )
        }
    }

    // MARK: - Diagnostics

    func documentCount(filter: ContentTypeFilter? = nil) async throws -> Int {
        return try await withConnection { conn in
            let rows: PostgresRowSequence
            if let filter {
                let ct = filter.rawValue
                rows = try await conn.query(
                    "SELECT COUNT(DISTINCT d.id)::int4 FROM documents d JOIN chunks c ON c.document_id = d.id WHERE d.content_type = \(ct)",
                    logger: self.logger
                )
            } else {
                rows = try await conn.query(
                    "SELECT COUNT(DISTINCT document_id)::int4 FROM chunks",
                    logger: self.logger
                )
            }
            for try await row in rows {
                let count = try row.decode(Int32.self, context: .default)
                return Int(count)
            }
            return 0
        }
    }

    func testConnection() async throws {
        try await withConnection { conn in
            let rows = try await conn.query("SELECT 1::int4", logger: self.logger)
            for try await _ in rows {}
        }
    }
}

enum VectorStoreError: LocalizedError {
    case invalidDSN
    var errorDescription: String? {
        switch self {
        case .invalidDSN: return "Invalid Postgres DSN"
        }
    }
}
