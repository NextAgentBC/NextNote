import SwiftUI

/// Markdown quick-insert toolbar — newbie-friendly snippet buttons.
/// Shown when file type is Markdown.
struct MarkdownToolbarView: View {
    var onInsert: (String, Int) -> Void  // (text to insert, cursor offset from start)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Voice dictation moved to the floating orb in the bottom-right
                // of the editor area (plus the global Fn hotkey). Toolbar no
                // longer owns it.

                // Headers
                Menu {
                    Button("H1  # Heading") { insert("# ", 2) }
                    Button("H2  ## Heading") { insert("## ", 3) }
                    Button("H3  ### Heading") { insert("### ", 4) }
                    Button("H4  #### Heading") { insert("#### ", 5) }
                } label: {
                    toolbarButton("H", hint: "Heading")
                }

                Divider().frame(height: 20)

                // Inline formatting
                toolbarAction("B", hint: "Bold") { insert("****", 2) }
                toolbarAction("I", hint: "Italic") { insert("**", 1) }
                toolbarAction("S", hint: "Strikethrough") { insert("~~~~", 2) }
                toolbarAction(icon: "chevron.left.forwardslash.chevron.right", hint: "Inline Code") {
                    insert("``", 1)
                }

                Divider().frame(height: 20)

                // Block elements
                toolbarAction(icon: "text.quote", hint: "Blockquote") {
                    insert("> ", 2)
                }
                toolbarAction(icon: "list.bullet", hint: "Bullet List") {
                    insert("- Item 1\n- Item 2\n- Item 3\n", 2)
                }
                toolbarAction(icon: "list.number", hint: "Numbered List") {
                    insert("1. Item 1\n2. Item 2\n3. Item 3\n", 3)
                }
                toolbarAction(icon: "checklist", hint: "Task List") {
                    insert("- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3\n", 6)
                }

                Divider().frame(height: 20)

                // Code block with language picker
                Menu {
                    Button("Plain") { insertCodeBlock("") }
                    Divider()
                    Button("Swift") { insertCodeBlock("swift") }
                    Button("Python") { insertCodeBlock("python") }
                    Button("JavaScript") { insertCodeBlock("javascript") }
                    Button("TypeScript") { insertCodeBlock("typescript") }
                    Button("Java") { insertCodeBlock("java") }
                    Button("C / C++") { insertCodeBlock("c") }
                    Button("Go") { insertCodeBlock("go") }
                    Button("Rust") { insertCodeBlock("rust") }
                    Divider()
                    Button("HTML") { insertCodeBlock("html") }
                    Button("CSS") { insertCodeBlock("css") }
                    Button("JSON") { insertCodeBlock("json") }
                    Button("YAML") { insertCodeBlock("yaml") }
                    Button("SQL") { insertCodeBlock("sql") }
                    Button("Bash") { insertCodeBlock("bash") }
                } label: {
                    toolbarButton(icon: "curlybraces", hint: "Code Block")
                }

                // Table
                Menu {
                    Button("2×2 Table") { insertTable(cols: 2, rows: 2) }
                    Button("3×3 Table") { insertTable(cols: 3, rows: 3) }
                    Button("4×3 Table") { insertTable(cols: 4, rows: 3) }
                    Button("5×3 Table") { insertTable(cols: 5, rows: 3) }
                } label: {
                    toolbarButton(icon: "tablecells", hint: "Table")
                }

                Divider().frame(height: 20)

                // Links & media
                toolbarAction(icon: "link", hint: "Link") {
                    insert("[link text](https://)", 1)
                }
                toolbarAction(icon: "photo", hint: "Image") {
                    insert("![alt text](image_url)", 2)
                }

                Divider().frame(height: 20)

                // Horizontal rule
                toolbarAction(icon: "minus", hint: "Divider") {
                    insert("\n---\n", 5)
                }

                // Math (basic)
                toolbarAction(icon: "function", hint: "Math") {
                    insert("$$\n\n$$", 3)
                }

                // Footnote
                toolbarAction(icon: "note.text", hint: "Footnote") {
                    insert("[^1]\n\n[^1]: ", 4)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 32)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Helpers

    private func insert(_ text: String, _ cursorOffset: Int) {
        onInsert(text, cursorOffset)
    }

    private func insertCodeBlock(_ language: String) {
        let block = "```\(language)\n\n```"
        let offset = 4 + language.count  // cursor after opening fence + newline
        insert(block, offset)
    }

    private func insertTable(cols: Int, rows: Int) {
        var table = "| "
        // Header row
        for c in 1...cols {
            table += "Column \(c) | "
        }
        table += "\n| "
        // Separator row
        for _ in 1...cols {
            table += "--- | "
        }
        table += "\n"
        // Data rows
        for r in 1...rows {
            table += "| "
            for c in 1...cols {
                table += "R\(r)C\(c) | "
            }
            table += "\n"
        }
        insert(table, 2)  // Cursor at first header cell
    }

    // MARK: - Button builders

    private func toolbarAction(_ label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(hint)
    }

    private func toolbarAction(icon: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(hint)
    }

    private func toolbarButton(_ label: String, hint: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .frame(width: 28, height: 24)
    }

    private func toolbarButton(icon: String, hint: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12))
            .frame(width: 28, height: 24)
    }
}
