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
                Label("运镜设置", systemImage: "camera.aperture")
                    .font(.headline)
                Spacer()
                Text("\(model.images.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("选择效果")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: effectColumns, spacing: 8) {
                ForEach(MotionEffect.allCases) { effect in
                    Button {
                        model.configuration.effect = effect
                    } label: {
                        Text(effect.title)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(model.configuration.effect == effect ? Color.white : Color.primary)
                            .background(
                                model.configuration.effect == effect ? Color.accentColor : Color.secondary.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            settingSlider(
                title: "Live Photo 时长",
                value: $model.configuration.duration,
                range: MotionConfiguration.durationRange,
                valueText: String(format: "%.1f 秒", model.configuration.duration),
                minimumText: "1.5 秒",
                maximumText: "5.0 秒"
            )
            settingSlider(
                title: "运镜强度",
                value: $model.configuration.intensity,
                range: MotionConfiguration.intensityRange,
                valueText: "\(Int(model.configuration.intensity * 100))%",
                minimumText: "轻微",
                maximumText: "明显"
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var effectColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
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
