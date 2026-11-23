import Foundation
import CoreGraphics

/// A saved Mac. The password lives in the Keychain, never here.
struct Host: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var hostname: String          // tailnet name, e.g. "my-mac"
    var port: UInt16 = 5900
    var username: String
    /// SF Symbol name; see `HostSymbol`. nil means `desktopcomputer`.
    var symbol: String?
    var lastConnected: Date?
    /// Per-Mac scroll speed; nil = use the global default (Settings).
    var scrollSpeed: Double?
    /// Send the password even when the Mac isn't reached through Tailscale, or asks for a plain
    /// VNC password instead of a macOS sign-in.
    var allowOutsideTailscale = false

    var displayLayout: DisplayLayout = .single
    var displayColumns = 2
    var displayRows = 2
    /// Zero means All; positive values are row-major display numbers.
    var selectedDisplay = 0

    var displayGrid: DisplayGrid {
        switch displayLayout {
        case .single: DisplayGrid(columns: 1, rows: 1)
        case .twoAcross: DisplayGrid(columns: 2, rows: 1)
        case .threeAcross: DisplayGrid(columns: 3, rows: 1)
        case .twoByTwo: DisplayGrid(columns: 2, rows: 2)
        case .custom: DisplayGrid(columns: displayColumns, rows: displayRows)
        }
    }

    init(id: UUID = UUID(), name: String, hostname: String, port: UInt16 = 5900, username: String,
         symbol: String? = nil, lastConnected: Date? = nil) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.symbol = symbol
        self.lastConnected = lastConnected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? 5900
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        lastConnected = try c.decodeIfPresent(Date.self, forKey: .lastConnected)
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed)
        displayLayout = try c.decodeIfPresent(DisplayLayout.self, forKey: .displayLayout) ?? .single
        displayColumns = try c.decodeIfPresent(Int.self, forKey: .displayColumns) ?? 2
        displayRows = try c.decodeIfPresent(Int.self, forKey: .displayRows) ?? 2
        selectedDisplay = try c.decodeIfPresent(Int.self, forKey: .selectedDisplay) ?? 0
        allowOutsideTailscale = try c.decodeIfPresent(Bool.self, forKey: .allowOutsideTailscale) ?? false
    }

    var symbolName: String { symbol ?? HostSymbol.defaultName }
}

/// The Mac icons offered in the editor.
enum HostSymbol {
    static let defaultName = "desktopcomputer"
    static let all = ["macmini", "laptopcomputer", "desktopcomputer", "macstudio", "display"]

    static func label(_ name: String) -> String {
        switch name {
        case "macmini": "Mac mini"
        case "laptopcomputer": "MacBook"
        case "macstudio": "Mac Studio"
        case "display": "iMac or display"
        default: "Desktop Mac"
        }
    }
}

enum DisplayLayout: String, Codable, CaseIterable {
    case single, twoAcross, threeAcross, twoByTwo, custom

    var label: String {
        switch self {
        case .single: "Single"
        case .twoAcross: "2 side by side"
        case .threeAcross: "3 side by side"
        case .twoByTwo: "2×2"
        case .custom: "Custom"
        }
    }
}

struct DisplayGrid: Equatable {
    let columns: Int
    let rows: Int
    var count: Int { columns * rows }

    init(columns: Int, rows: Int) {
        self.columns = min(max(columns, 1), 4)
        self.rows = min(max(rows, 1), 4)
    }

    func rects(framebufferSize size: CGSize) -> [CGRect] {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= 1, size.height >= 1,
              size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) else { return [] }
        let width = Int(size.width), height = Int(size.height)
        // Quotients and remainders avoid multiplying framebuffer dimensions.
        func edge(_ length: Int, _ index: Int, _ divisions: Int) -> Int {
            (length / divisions) * index + (length % divisions) * index / divisions
        }
        return (0..<count).map { index in
            let column = index % columns, row = index / columns
            let x = edge(width, column, columns), y = edge(height, row, rows)
            return CGRect(x: x, y: y,
                          width: edge(width, column + 1, columns) - x,
                          height: edge(height, row + 1, rows) - y)
        }
    }
}
