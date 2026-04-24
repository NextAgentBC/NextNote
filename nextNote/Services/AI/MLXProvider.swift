import Foundation
import MLXLMCommon

// UserInput is a plain struct from MLXLMCommon that doesn't declare Sendable.
// Adding @unchecked conformance so we can pass it across async suspension points
// without Swift 6 region-isolation errors. Safe: UserInput contains only Strings.
extension UserInput: @retroactive @unchecked Sendable {}

/// On-device LLM provider backed by MLX Swift.
/// Stays on the main actor (same as the existing AIService) so the MLX
/// model container is always accessed from a single isolation domain.
@MainActor
final class MLXProvider: LLMProvider {

    private let manager: AIModelManager

    private(set) var lastTokensPerSecond: Double = 0

    init(manager: AIModelManager = AIModelManager.shared) {
        self.manager = manager
    }

    // MARK: - LLMProvider

    func generate(messages: [LLMMessage], parameters: LLMParameters) async throws -> String {
        guard let container = manager.container else {
            throw AIError.modelNotLoaded
        }

        // Use the same UserInput(chat:) pattern as the original AIService.
        // Type inference resolves the element type from MLXLMCommon.
        let input = try await container.prepare(
            input: UserInput(chat: messages.map { msg in
                switch msg.role {
                case .system:    return .system(msg.content)
                case .user:      return .user(msg.content)
                case .assistant: return .assistant(msg.content)
                }
            })
        )

        let genParams = GenerateParameters(
            maxTokens: parameters.maxTokens,
            temperature: parameters.temperature
        )

        var result = ""
        let stream = try await container.generate(input: input, parameters: genParams)

        for try await generation in stream {
            switch generation {
            case .chunk(let text):
                result += text
            case .info(let info):
                lastTokensPerSecond = info.tokensPerSecond
            default:
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateStream(messages: [LLMMessage], parameters: LLMParameters) -> AsyncThrowingStream<String, Error> {
        let container = manager.container          // snapshot while on MainActor
        let msgs = messages
        let genParams = GenerateParameters(
            maxTokens: parameters.maxTokens,
            temperature: parameters.temperature
        )

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                do {
                    guard let c = container else { throw AIError.modelNotLoaded }

                    let input = try await c.prepare(
                        input: UserInput(chat: msgs.map { msg in
                            switch msg.role {
                            case .system:    return .system(msg.content)
                            case .user:      return .user(msg.content)
                            case .assistant: return .assistant(msg.content)
                            }
                        })
                    )
                    let stream = try await c.generate(input: input, parameters: genParams)

                    for try await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                        case .info(let info):
                            self?.lastTokensPerSecond = info.tokensPerSecond
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testConnection() async throws {
        guard manager.container != nil else {
            throw AIError.modelNotLoaded
        }
    }
}
