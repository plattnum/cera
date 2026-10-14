import AppKit

/// Colors comments, strings, numbers, keywords, and constants inside fenced code
/// blocks, based on the language named after the opening fence.
struct CodeHighlighter {
    let colors: Theme.Syntax

    private enum CommentStyle { case hash, slashes, none }

    private struct Language {
        let comments: CommentStyle
        let keywords: Set<String>
        let builtins: Set<String>
    }

    private static let atoms: Set<String> = ["true", "false", "null", "nil", "None", "True", "False", "undefined", "NaN"]

    private static let shell = Language(
        comments: .hash,
        keywords: ["if", "then", "do", "else", "elif", "while", "until", "for", "in", "esac", "fi", "done", "case",
                   "exit", "set", "unset", "export", "function", "return", "local"],
        builtins: ["awk", "bash", "cat", "cd", "chmod", "chown", "clear", "cp", "curl", "cut", "diff", "echo", "find",
                   "git", "grep", "kill", "ln", "ls", "make", "mkdir", "mv", "node", "npm", "ps", "rm", "rmdir", "sed",
                   "sh", "sort", "source", "sleep", "ssh", "sudo", "tee", "touch", "vi", "vim", "wc", "wget", "zsh"]
    )

    private static let python = Language(
        comments: .hash,
        keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
                   "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
                   "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"],
        builtins: ["print", "len", "range", "str", "int", "float", "list", "dict", "set", "tuple", "open", "self"]
    )

    private static let cLike = Language(
        comments: .slashes,
        keywords: ["as", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "defer",
                   "do", "else", "enum", "export", "extends", "extension", "fn", "for", "func", "function", "guard",
                   "if", "impl", "import", "in", "interface", "let", "match", "mod", "mut", "new", "package", "private",
                   "protocol", "pub", "public", "return", "self", "static", "struct", "super", "switch", "this", "throw",
                   "throws", "trait", "try", "type", "typeof", "use", "var", "void", "where", "while", "yield"],
        builtins: []
    )

    private static let config = Language(comments: .hash, keywords: [], builtins: [])

    private static func language(named name: String) -> Language? {
        switch name {
        case "bash", "sh", "shell", "zsh", "console", "shellscript": return shell
        case "python", "py": return python
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "swift", "rust", "rs", "go", "c", "cpp", "c++",
             "h", "java", "kotlin", "kt", "cs", "csharp", "scala", "php", "dart", "json", "css", "scss":
            return cLike
        case "yaml", "yml", "toml", "ini", "conf", "dockerfile", "makefile", "ruby", "rb", "r", "perl":
            return config
        default: return nil
        }
    }

    /// Highlights the code in `range` (the lines between the fences).
    /// `text` is the storage's string, passed in so it isn't copied for every block.
    func highlight(_ storage: NSTextStorage, text: NSString, range: NSRange, language name: String) {
        guard let language = Self.language(named: name.lowercased()) else { return }
        var index = range.location
        let end = NSMaxRange(range)
        var inBlockComment = false

        func color(_ color: NSColor, _ from: Int, _ to: Int) {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: from, length: to - from))
        }
        func char(_ i: Int) -> unichar { i < end ? text.character(at: i) : 0 }
        func isWordChar(_ c: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || c == 95 // _
        }
        func lineEnd(from i: Int) -> Int {
            var j = i
            while j < end, char(j) != 10 { j += 1 }
            return j
        }

        while index < end {
            let c = char(index)

            if inBlockComment {
                let start = index
                while index < end, !(char(index) == 42 && char(index + 1) == 47) { index += 1 } // */
                index = min(end, index + 2)
                color(colors.comment, start, index)
                inBlockComment = false
                continue
            }

            // Comments
            let previous: unichar = index > range.location ? char(index - 1) : 10
            let atWordBoundary = previous == 10 || previous == 32 || previous == 9
            if language.comments == .hash, c == 35, atWordBoundary { // #
                let stop = lineEnd(from: index)
                color(colors.comment, index, stop)
                index = stop
                continue
            }
            if language.comments == .slashes, c == 47, char(index + 1) == 47 { // //
                let stop = lineEnd(from: index)
                color(colors.comment, index, stop)
                index = stop
                continue
            }
            if language.comments == .slashes, c == 47, char(index + 1) == 42 { // /*
                inBlockComment = true
                continue
            }

            // Strings
            if c == 34 || c == 39 || c == 96 { // " ' `
                let start = index
                index += 1
                while index < end, char(index) != c, char(index) != 10 {
                    if char(index) == 92 { index += 1 } // backslash escape
                    index += 1
                }
                index = min(end, index + 1)
                color(colors.string, start, index)
                continue
            }

            // Numbers
            if c >= 48, c <= 57, !isWordChar(previous) {
                let start = index
                while index < end, isWordChar(char(index)) || char(index) == 46 { index += 1 }
                color(colors.number, start, index)
                continue
            }

            // Words
            if isWordChar(c) {
                let start = index
                while index < end, isWordChar(char(index)) { index += 1 }
                let word = text.substring(with: NSRange(location: start, length: index - start))
                if language.keywords.contains(word) {
                    color(colors.keyword, start, index)
                } else if Self.atoms.contains(word) {
                    color(colors.atom, start, index)
                } else if language.builtins.contains(word), !isWordChar(previous) {
                    color(colors.builtin, start, index)
                }
                continue
            }

            index += 1
        }
    }
}
