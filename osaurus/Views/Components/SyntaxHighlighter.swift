//
//  SyntaxHighlighter.swift
//  osaurus
//
//  Simple syntax highlighter for code blocks
//

import SwiftUI

struct SyntaxHighlighter {
  
  // MARK: - Token Types
  enum TokenType {
    case keyword
    case string
    case comment
    case number
    case function
    case type
    case constant
    case plain
  }
  
  struct Token {
    let text: String
    let type: TokenType
  }
  
  // MARK: - Language-specific Keywords
  private static let pythonKeywords = Set([
    "def", "class", "if", "else", "elif", "for", "while", "return", "import", "from",
    "try", "except", "finally", "with", "as", "lambda", "yield", "async", "await",
    "pass", "break", "continue", "raise", "assert", "del", "global", "nonlocal",
    "True", "False", "None", "and", "or", "not", "in", "is"
  ])
  
  private static let swiftKeywords = Set([
    "func", "class", "struct", "enum", "protocol", "extension", "var", "let", "if",
    "else", "for", "while", "return", "import", "guard", "switch", "case", "default",
    "break", "continue", "fallthrough", "repeat", "defer", "do", "catch", "throw",
    "try", "throws", "async", "await", "actor", "init", "deinit", "subscript",
    "true", "false", "nil", "self", "Self", "super", "where", "in", "is", "as"
  ])
  
  private static let jsKeywords = Set([
    "function", "const", "let", "var", "if", "else", "for", "while", "return",
    "import", "export", "from", "class", "extends", "new", "this", "super",
    "try", "catch", "finally", "throw", "async", "await", "yield", "break",
    "continue", "switch", "case", "default", "typeof", "instanceof", "delete",
    "true", "false", "null", "undefined"
  ])
  
  private static let rustKeywords = Set([
    "fn", "let", "mut", "const", "if", "else", "for", "while", "loop", "return",
    "impl", "trait", "struct", "enum", "mod", "pub", "use", "match", "break",
    "continue", "true", "false", "self", "Self", "super", "crate", "async", "await",
    "where", "type", "as", "ref", "move", "static", "extern", "unsafe"
  ])
  
  private static let goKeywords = Set([
    "func", "var", "const", "if", "else", "for", "return", "import", "package",
    "type", "struct", "interface", "map", "chan", "go", "defer", "select", "range",
    "switch", "case", "default", "break", "continue", "fallthrough", "goto",
    "true", "false", "nil", "make", "new", "len", "cap", "append", "copy", "delete"
  ])
  
  // MARK: - Color Scheme
  static func color(for tokenType: TokenType, isDark: Bool) -> Color {
    switch tokenType {
    case .keyword:
      return isDark ? Color(hex: "ff79c6") : Color(hex: "d73a49")  // Pink/Red
    case .string:
      return isDark ? Color(hex: "50fa7b") : Color(hex: "032f62")  // Green/Blue
    case .comment:
      return isDark ? Color(hex: "6272a4") : Color(hex: "6a737d")  // Gray
    case .number:
      return isDark ? Color(hex: "bd93f9") : Color(hex: "005cc5")  // Purple/Blue
    case .function:
      return isDark ? Color(hex: "8be9fd") : Color(hex: "6f42c1")  // Cyan/Purple
    case .type:
      return isDark ? Color(hex: "ffb86c") : Color(hex: "d73a49")  // Orange/Red
    case .constant:
      return isDark ? Color(hex: "bd93f9") : Color(hex: "005cc5")  // Purple/Blue
    case .plain:
      return isDark ? Color(hex: "f8f8f2") : Color(hex: "24292e")  // White/Black
    }
  }
  
  // MARK: - Tokenization
  static func tokenize(_ code: String, language: String?) -> [Token] {
    let lang = language?.lowercased() ?? ""
    let keywords = getKeywords(for: lang)
    
    var tokens: [Token] = []
    var currentIndex = code.startIndex
    
    while currentIndex < code.endIndex {
      let char = code[currentIndex]
      
      // Skip whitespace
      if char.isWhitespace {
        let wsStart = currentIndex
        while currentIndex < code.endIndex && code[currentIndex].isWhitespace {
          currentIndex = code.index(after: currentIndex)
        }
        tokens.append(Token(text: String(code[wsStart..<currentIndex]), type: .plain))
        continue
      }
      
      // Comments
      if currentIndex < code.index(before: code.endIndex) {
        let nextChar = code[code.index(after: currentIndex)]
        
        // Single-line comment (// or #)
        if (char == "/" && nextChar == "/") || (char == "#" && lang == "python") {
          let commentStart = currentIndex
          while currentIndex < code.endIndex && code[currentIndex] != "\n" {
            currentIndex = code.index(after: currentIndex)
          }
          tokens.append(Token(text: String(code[commentStart..<currentIndex]), type: .comment))
          continue
        }
        
        // Multi-line comment (/* */)
        if char == "/" && nextChar == "*" {
          let commentStart = currentIndex
          currentIndex = code.index(after: currentIndex)
          currentIndex = code.index(after: currentIndex)
          while currentIndex < code.index(before: code.endIndex) {
            if code[currentIndex] == "*" && code[code.index(after: currentIndex)] == "/" {
              currentIndex = code.index(after: currentIndex)
              currentIndex = code.index(after: currentIndex)
              break
            }
            currentIndex = code.index(after: currentIndex)
          }
          tokens.append(Token(text: String(code[commentStart..<currentIndex]), type: .comment))
          continue
        }
      }
      
      // Strings
      if char == "\"" || char == "'" {
        let quote = char
        let stringStart = currentIndex
        currentIndex = code.index(after: currentIndex)
        
        while currentIndex < code.endIndex {
          let c = code[currentIndex]
          if c == quote {
            currentIndex = code.index(after: currentIndex)
            break
          }
          if c == "\\" && currentIndex < code.index(before: code.endIndex) {
            currentIndex = code.index(after: currentIndex)
          }
          currentIndex = code.index(after: currentIndex)
        }
        tokens.append(Token(text: String(code[stringStart..<currentIndex]), type: .string))
        continue
      }
      
      // Numbers
      if char.isNumber {
        let numStart = currentIndex
        while currentIndex < code.endIndex && (code[currentIndex].isNumber || code[currentIndex] == ".") {
          currentIndex = code.index(after: currentIndex)
        }
        tokens.append(Token(text: String(code[numStart..<currentIndex]), type: .number))
        continue
      }
      
      // Identifiers and keywords
      if char.isLetter || char == "_" {
        let wordStart = currentIndex
        while currentIndex < code.endIndex && (code[currentIndex].isLetter || code[currentIndex].isNumber || code[currentIndex] == "_") {
          currentIndex = code.index(after: currentIndex)
        }
        let word = String(code[wordStart..<currentIndex])
        
        let tokenType: TokenType
        if keywords.contains(word) {
          tokenType = .keyword
        } else if word.first?.isUppercase == true && lang == "swift" {
          tokenType = .type
        } else {
          tokenType = .plain
        }
        
        tokens.append(Token(text: word, type: tokenType))
        continue
      }
      
      // Single character
      tokens.append(Token(text: String(char), type: .plain))
      currentIndex = code.index(after: currentIndex)
    }
    
    return tokens
  }
  
  private static func getKeywords(for language: String) -> Set<String> {
    switch language {
    case "python", "py":
      return pythonKeywords
    case "swift":
      return swiftKeywords
    case "javascript", "js", "typescript", "ts", "jsx", "tsx":
      return jsKeywords
    case "rust", "rs":
      return rustKeywords
    case "go", "golang":
      return goKeywords
    default:
      return pythonKeywords.union(swiftKeywords).union(jsKeywords)
    }
  }
  
  // MARK: - Build Attributed String
  static func highlight(_ code: String, language: String?, baseWidth: CGFloat, isDark: Bool) -> Text {
    let tokens = tokenize(code, language: language)
    
    if tokens.isEmpty {
      return Text(code)
        .font(Typography.code(baseWidth))
        .foregroundColor(color(for: .plain, isDark: isDark))
    }
    
    var result = Text("")
    
    for token in tokens {
      let coloredText = Text(token.text)
        .font(Typography.code(baseWidth))
        .foregroundColor(color(for: token.type, isDark: isDark))
      result = result + coloredText
    }
    
    return result
  }
}
