import Foundation

enum MotionEffect: String, CaseIterable, Identifiable, Sendable {
    case zoomIn
    case zoomOut
    case panLeft
    case panRight
    case panUp
    case panDown
    case diagonal

    var id: Self { self }

    var title: String {
        switch self {
        case .zoomIn: "推近"
        case .zoomOut: "拉远"
        case .panLeft: "左移"
        case .panRight: "右移"
        case .panUp: "上移"
        case .panDown: "下移"
        case .diagonal: "斜向"
        }
    }
}

struct MotionConfiguration: Sendable {
    var effect: MotionEffect = .zoomIn
    var duration: Double = 3
    var intensity: Double = 0.075

    static let durationRange = 1.5...5.0
    static let intensityRange = 0.02...0.20
}
