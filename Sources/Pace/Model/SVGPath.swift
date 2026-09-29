import Foundation
import CoreGraphics

/// Minimal parser for the absolute `M`, `C`, `L`, `Z` commands used by the apple artwork.
enum SVGPath {
    static func cgPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var token = ""

        func flush() {
            if let v = Double(token) { numbers.append(CGFloat(v)) }
            token = ""
        }
        func apply() {
            switch command {
            case "M":
                if numbers.count >= 2 { path.move(to: CGPoint(x: numbers[0], y: numbers[1])) }
                numbers.removeAll()
            case "L":
                if numbers.count >= 2 { path.addLine(to: CGPoint(x: numbers[0], y: numbers[1])) }
                numbers.removeAll()
            case "C":
                while numbers.count >= 6 {
                    path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                                  control1: CGPoint(x: numbers[0], y: numbers[1]),
                                  control2: CGPoint(x: numbers[2], y: numbers[3]))
                    numbers.removeFirst(6)
                }
            case "Z":
                path.closeSubpath()
                numbers.removeAll()
            default:
                numbers.removeAll()
            }
        }

        for ch in d {
            if ch.isLetter {
                flush(); apply()
                command = ch
                if command == "Z" { apply() }
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" {
                flush(); token = "-"
            } else {
                token.append(ch)
            }
        }
        flush(); apply()
        return path
    }
}

/// Apple artwork from docs/DESIGN.md section 7, in a 24 x 24 box.
enum AppleArt {
    static let body = "M12 8.2C10.6 6.9 7.9 6.5 6 8C3.7 9.8 3.5 13.4 4.6 16.2C5.6 18.8 7.6 21.5 9.6 21.5C10.6 21.5 11.1 21 12 21C12.9 21 13.4 21.5 14.4 21.5C16.4 21.5 18.4 18.8 19.4 16.2C20.5 13.4 20.3 9.8 18 8C16.1 6.5 13.4 6.9 12 8.2Z"
    static let stem = "M12 8.2C12 6.1 12.4 4.5 13.4 3.3"
    static let leaf = "M12.9 5.3C13.6 3.3 15.8 2.5 17.8 3C17.2 5 15 6 12.9 5.3Z"

    static let bodyPath = SVGPath.cgPath(body)
    static let stemPath = SVGPath.cgPath(stem)
    static let leafPath = SVGPath.cgPath(leaf)

    /// The body spans y = 6.5 ... 21.5 in the 24-box. Fill rises from the bottom.
    static let bodyTop: CGFloat = 6.5
    static let bodyBottom: CGFloat = 21.5
}
