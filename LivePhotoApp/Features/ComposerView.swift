import PhotosUI
import SwiftUI

struct ComposerView: View {
    @StateObject private var model = ComposerModel()
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
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
                    Label("选择照片（最多 20 张）", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .onChange(of: selectedItems) { _, items in
                        Task { await model.load(items) }
                    }

                    if !model.images.isEmpty {
                        controls
                    }

                Button {
                    Task { await model.generateAndSave() }
                } label: {
                    HStack {
                        if model.isWorking {
                            ProgressView()
                        }
                        Text(model.isWorking ? model.status : "生成并保存 \(model.images.count) 张 Live Photo")
                    }
                    .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.image == nil || model.isWorking)

                    if !model.status.isEmpty && !model.isWorking {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(model.didSucceed ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .navigationTitle("Live Photo")
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.secondary.opacity(0.12))

            if let image = model.image {
                MotionPreview(image: image, configuration: model.configuration)
            } else {
                ContentUnavailableView(
                    "选择静态照片",
                    systemImage: "livephoto",
                    description: Text("可批量选择，配置运镜后保存到系统照片")
                )
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxHeight: 560)
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
                            .frame(width: 54, height: 72)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("运镜效果")
                Spacer()
                Text("\(model.images.count) 张")
                    .foregroundStyle(.secondary)
            }

            Picker("运镜效果", selection: $model.configuration.effect) {
                ForEach(MotionEffect.allCases) { effect in
                    Text(effect.title).tag(effect)
                }
            }
            .pickerStyle(.menu)

            settingSlider(
                title: "时长",
                value: $model.configuration.duration,
                range: MotionConfiguration.durationRange,
                valueText: String(format: "%.1f 秒", model.configuration.duration)
            )
            settingSlider(
                title: "幅度",
                value: $model.configuration.intensity,
                range: MotionConfiguration.intensityRange,
                valueText: "\(Int(model.configuration.intensity * 100))%"
            )
        }
        .padding()
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

private struct MotionPreview: View {
    let image: UIImage
    let configuration: MotionConfiguration
    @State private var progress = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .onAppear { restart() }
            .onChange(of: configuration.effect) { _, _ in restart() }
            .onChange(of: configuration.duration) { _, _ in restart() }
            .onChange(of: configuration.intensity) { _, _ in restart() }
    }

    private var scale: CGFloat {
        let amount = configuration.intensity
        switch configuration.effect {
        case .zoomIn: return 1 + (progress ? amount : 0)
        case .zoomOut: return 1 + (progress ? 0 : amount)
        default: return 1 + amount
        }
    }

    private var offset: CGSize {
        let amount = configuration.intensity * 140
        switch configuration.effect {
        case .panLeft: return CGSize(width: progress ? -amount : amount, height: 0)
        case .panRight: return CGSize(width: progress ? amount : -amount, height: 0)
        case .panUp: return CGSize(width: 0, height: progress ? -amount : amount)
        case .panDown: return CGSize(width: 0, height: progress ? amount : -amount)
        case .diagonal: return CGSize(width: progress ? amount : -amount, height: progress ? -amount : amount)
        default: return .zero
        }
    }

    private func restart() {
        progress = false
        withAnimation(.easeInOut(duration: configuration.duration).repeatForever(autoreverses: false)) {
            progress = true
        }
    }
}
