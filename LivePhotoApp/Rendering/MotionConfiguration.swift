import Foundation

enum EffectMode: String, CaseIterable, Identifiable, Sendable {
    case motion, shape, combined, random
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
    var mode: EffectMode = .motion
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
        result.mode = .combined
        result.motionEffect = MotionEffect.allCases.randomElement() ?? .zoomIn
        result.shapeEffect = ShapeEffect.allCases.randomElement() ?? .verticalStretch
        return result
    }

    var previewConfiguration: Self {
        guard mode == .random else { return self }
        var result = self
        result.mode = .combined
        return result
    }
}
