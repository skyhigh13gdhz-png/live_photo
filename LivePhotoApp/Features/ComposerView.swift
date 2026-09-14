import PhotosUI
import SwiftUI

struct ComposerView: View {
    @StateObject private var model = ComposerModel()
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview

                    if model.images.count > 1 {
                        imageStrip
                    }

                    PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        Label("选择 / 更换照片", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: selectedItems) { _, items in
                        Task { await model.load(items) }
                    }

                    if !model.images.isEmpty {
                        controls
                    }

                    if !model.status.isEmpty && !model.isWorking {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(model.didSucceed ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Live Photo")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                generateBar
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.secondary.opacity(0.12))

            if let image = model.image {
                RenderedEffectPreview(image: image, configuration: model.previewConfiguration)
            } else {
                ContentUnavailableView(
                    "选择静态照片",
                    systemImage: "livephoto",
                    description: Text("可批量选择，配置运镜后保存到系统照片")
                )
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if !model.images.isEmpty {
                Text("\(model.selectedIndex + 1)/\(model.images.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.images.enumerated()), id: \.offset) { index, image in
                    Button {
                        model.selectedIndex = index
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(index == model.selectedIndex ? Color.accentColor : .clear, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览第 \(index + 1) 张照片")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("效果设置", systemImage: "camera.aperture")
                    .font(.headline)
                Spacer()
                Text("\(model.images.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("效果类型")
                .font(.subheadline.weight(.medium))

            Picker("效果类型", selection: $model.configuration.mode) {
                ForEach(EffectMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if model.configuration.mode == .random {
                effectTitle("随机内容")
                Picker("随机内容", selection: $model.configuration.randomScope) {
                    ForEach(RandomScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.configuration.randomScope) { _, _ in
                    model.randomizeAll()
                }

                Label("每张照片独立抽取；预览即实际导出效果", systemImage: "shuffle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("重抽本张", systemImage: "arrow.clockwise") {
                        model.randomizeCurrent()
                    }
                    Button("重抽全部", systemImage: "shuffle") {
                        model.randomizeAll()
                    }
                }
                .buttonStyle(.bordered)

                Text(randomResultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if model.configuration.appliesMotion {
                    effectTitle("选择运镜")
                    optionGrid(MotionEffect.allCases, selection: $model.configuration.motionEffect)
                }
                if model.configuration.appliesShape {
                    effectTitle("选择形变")
                    optionGrid(ShapeEffect.allCases, selection: $model.configuration.shapeEffect)
                }
            }

            Toggle("高级参数", isOn: $model.configuration.advancedEnabled)
                .font(.subheadline.weight(.semibold))

            if model.configuration.advancedEnabled {
                settingSlider(
                    title: "Live Photo 时长",
                    value: $model.configuration.duration,
                    range: MotionConfiguration.durationRange,
                    valueText: String(format: "%.1f 秒", model.configuration.duration),
                    minimumText: "1.5 秒",
                    maximumText: "5.0 秒"
                )
                if model.configuration.appliesMotion {
                    settingSlider(
                        title: "运镜强度",
                        value: $model.configuration.motionIntensity,
                        range: MotionConfiguration.motionIntensityRange,
                        valueText: "\(Int(model.configuration.motionIntensity * 100))%",
                        minimumText: "轻微",
                        maximumText: "明显"
                    )
                }
                if model.configuration.appliesShape {
                    settingSlider(
                        title: "形变强度",
                        value: $model.configuration.shapeIntensity,
                        range: MotionConfiguration.shapeIntensityRange,
                        valueText: String(format: "%.2fx", model.configuration.shapeIntensity),
                        minimumText: "轻微",
                        maximumText: "明显"
                    )
                }
                Text("形变 1.00x 对应 Mac 脚本的默认强度；运镜强度为 iOS 统一幅度控制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var effectColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private func effectTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium))
    }

    private func optionGrid<Option: CaseIterable & Identifiable & Hashable>(
        _ options: Option.AllCases,
        selection: Binding<Option>
    ) -> some View where Option.AllCases: RandomAccessCollection {
        LazyVGrid(columns: effectColumns, spacing: 8) {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(optionTitle(option))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection.wrappedValue == option ? Color.white : Color.primary)
                        .background(
                            selection.wrappedValue == option ? Color.accentColor : Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func optionTitle<Option>(_ option: Option) -> String {
        if let motion = option as? MotionEffect { return motion.title }
        if let shape = option as? ShapeEffect { return shape.title }
        return String(describing: option)
    }

    private var randomResultText: String {
        let config = model.previewConfiguration
        switch config.mode {
        case .combined: return "当前第 \(model.selectedIndex + 1) 张：\(config.motionEffect.title) + \(config.shapeEffect.title)"
        case .motion: return "当前第 \(model.selectedIndex + 1) 张：\(config.motionEffect.title)"
        case .shape: return "当前第 \(model.selectedIndex + 1) 张：\(config.shapeEffect.title)"
        case .random: return "选择照片后生成随机结果"
        }
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String,
        minimumText: String,
        maximumText: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
            }
            Slider(value: value, in: range)
            HStack {
                Text(minimumText)
                Spacer()
                Text(maximumText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var generateBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await model.generateAndSave() }
            } label: {
                HStack(spacing: 8) {
                    if model.isWorking {
                        ProgressView().tint(.white)
                    }
                    Text(model.isWorking ? model.status : "生成 \(model.images.count) 张 Live Photo")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.image == nil || model.isWorking)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

private struct RenderedEffectPreview: View {
    let image: UIImage
    let configuration: MotionConfiguration
    private let context = CIContext(options: [.cacheIntermediates: false])

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            if let frame = renderedFrame(at: timeline.date) {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
    }

    private func renderedFrame(at date: Date) -> CGImage? {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: configuration.duration) / configuration.duration
        guard let renderer = try? StablePushRenderer(
            image: image,
            configuration: configuration,
            outputSize: CGSize(width: 270, height: 480)
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 270, height: 480)
        return context.createCGImage(renderer.frame(progress: progress), from: bounds)
    }
}
