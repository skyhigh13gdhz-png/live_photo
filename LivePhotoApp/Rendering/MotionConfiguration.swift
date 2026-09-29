import Foundation

enum CanvasRatio: String, CaseIterable, Identifiable, Sendable {
    case original, portrait9x16, portrait4x5, square
    var id: Self { self }
    var title: String {
        switch self {
        case .original: "原图"
        case .portrait9x16: "9:16"
        case .portrait4x5: "4:5"
        case .square: "1:1"
        }
    }

    func outputSize(for sourceSize: CGSize) -> CGSize {
        switch self {
        case .portrait9x16: return CGSize(width: 1080, height: 1920)
        case .portrait4x5: return CGSize(width: 1536, height: 1920)
        case .square: return CGSize(width: 1440, height: 1440)
        case .original:
            let ratio = max(sourceSize.width, 1) / max(sourceSize.height, 1)
            if ratio >= 1 {
                return CGSize(width: 1920, height: Self.even(1920 / ratio))
            }
            return CGSize(width: Self.even(1920 * ratio), height: 1920)
        }
    }

    func aspectRatio(for sourceSize: CGSize) -> CGFloat {
        let size = outputSize(for: sourceSize)
        return size.width / size.height
    }

    func previewSize(for sourceSize: CGSize) -> CGSize {
        let ratio = aspectRatio(for: sourceSize)
        if ratio >= 1 {
            return CGSize(width: 480, height: Self.even(480 / ratio))
        }
        return CGSize(width: Self.even(480 * ratio), height: 480)
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }
}

enum EffectMode: String, CaseIterable, Identifiable, Sendable {
    case random, combined, motion, shape
    var id: Self { self }
    var title: String {
        switch self {
        case .motion: "运镜"
        case .shape: "形变"
        case .combined: "组合"
        case .random: "随机"
        }
    }
}

enum RandomScope: String, CaseIterable, Identifiable, Sendable {
    case combined, motion, shape
    var id: Self { self }
    var title: String {
        switch self {
        case .combined: "组合随机"
        case .motion: "仅运镜"
        case .shape: "仅形变"
        }
    }
}

enum MotionEffect: String, CaseIterable, Identifiable, Hashable, Sendable {
    case zoomIn, zoomOut, panLeft, panRight, panUp, panDown, diagonal
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

enum ShapeEffect: String, CaseIterable, Identifiable, Hashable, Sendable {
    case verticalStretch, horizontalStretch, shear, roll, lensBreathing
    var id: Self { self }
    var title: String {
        switch self {
        case .verticalStretch: "纵向伸缩"
        case .horizontalStretch: "横向伸缩"
        case .shear: "仿射倾斜"
        case .roll: "轻微侧倾"
        case .lensBreathing: "镜头呼吸"
        }
    }
}

struct MotionConfiguration: Sendable {
    var canvasRatio: CanvasRatio = .original
    var mode: EffectMode = .random
    var randomScope: RandomScope = .combined
    var motionEffect: MotionEffect = .zoomIn
    var shapeEffect: ShapeEffect = .verticalStretch
    var advancedEnabled = false
    var duration: Double = 3
    var motionIntensity: Double = 0.075
    var shapeIntensity: Double = 1

    static let durationRange = 1.5...5.0
    static let motionIntensityRange = 0.02...0.20
    static let shapeIntensityRange = 0.25...2.0

    var appliesMotion: Bool { mode == .motion || mode == .combined || mode == .random }
    var appliesShape: Bool { mode == .shape || mode == .combined || mode == .random }

    func resolvedForExport() -> Self {
        guard mode == .random else { return self }
        var result = self
        switch randomScope {
        case .combined:
            result.mode = .combined
            result.motionEffect = MotionEffect.allCases.randomElement() ?? .zoomIn
            result.shapeEffect = ShapeEffect.allCases.randomElement() ?? .verticalStretch
        case .motion:
            result.mode = .motion
            result.motionEffect = MotionEffect.allCases.randomElement() ?? .zoomIn
        case .shape:
            result.mode = .shape
            result.shapeEffect = ShapeEffect.allCases.randomElement() ?? .verticalStretch
        }
        return result
    }
}
