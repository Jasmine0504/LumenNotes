import AVFoundation
import MapKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
struct AttachmentCard: View {
    @Environment(FontTheme.self) private var theme
    let attachment: Attachment
    var onPreview: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onPreview) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(theme.font(for: .body).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contentSurface(radius: 16, padding: 12)
        .contextMenu {
            Button(action: onPreview) {
                Label("预览", systemImage: "eye")
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("删除附件", systemImage: "trash")
                }
            }
        }
    }

    private var title: String {
        switch attachment.kind {
        case .photo: attachment.fileName.isEmpty ? "照片" : attachment.fileName
        case .pdf: attachment.fileName
        case .scan: "扫描文稿 · \(attachment.metadata.pageCount ?? 1) 页"
        case .audio: "录音 · \(formattedDuration)"
        case .link: attachment.metadata.linkTitle ?? attachment.metadata.linkHost ?? "网页链接"
        case .map: attachment.metadata.mapTitle ?? "地点"
        }
    }

    private var subtitle: String {
        switch attachment.kind {
        case .photo:
            return "照片附件 · 点击全屏预览"
        case .pdf, .scan:
            let text = attachment.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "PDF 附件 · 可标注" : String(text.prefix(100))
        case .audio:
            let text = attachment.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "录音附件" : String(text.prefix(100))
        case .link:
            return attachment.metadata.linkHost ?? attachment.metadata.linkURL ?? "网页链接"
        case .map:
            if let lat = attachment.metadata.latitude, let lon = attachment.metadata.longitude {
                return String(format: "%.4f, %.4f", lat, lon)
            }
            return "地图地点"
        }
    }

    private var formattedDuration: String {
        let value = Int(attachment.metadata.durationSeconds ?? 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LumenTheme.accent.opacity(0.10))
            switch attachment.kind {
            case .photo, .scan:
                if let image = UIImage(data: attachment.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: attachment.kind.symbolName)
                        .font(.title3)
                        .foregroundStyle(LumenTheme.accent)
                }
            default:
                Image(systemName: attachment.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(LumenTheme.accent)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct AttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var attachment: Attachment
    @State private var isAnnotating = false

    var body: some View {
        NavigationStack {
            Group {
                switch attachment.kind {
                case .photo:
                    photo
                case .pdf, .scan:
                    pdf
                case .audio:
                    audio
                case .link:
                    link
                case .map:
                    map
                }
            }
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
                if attachment.kind == .pdf || attachment.kind == .scan {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isAnnotating ? "阅读" : "标注") {
                            isAnnotating.toggle()
                        }
                    }
                }
            }
        }
    }

    private var photo: some View {
        Group {
            if let image = UIImage(data: attachment.data) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                .background(Color.black)
            } else {
                ContentUnavailableView("无法读取照片", systemImage: "photo.badge.exclamationmark")
            }
        }
    }

    private var pdf: some View {
        PDFAnnotatorView(
            data: attachment.data,
            annotationData: Binding(
                get: { attachment.annotationData },
                set: { value in
                    attachment.annotationData = value
                    try? modelContext.save()
                }
            ),
            isAnnotating: isAnnotating
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var audio: some View {
        AudioAttachmentPlayer(attachment: attachment)
    }

    private var link: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LumenTheme.accent)
            if let urlString = attachment.metadata.linkURL, let url = URL(string: urlString) {
                Text(attachment.metadata.linkTitle ?? url.host ?? "网页链接")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Link(destination: url) {
                    Label("在浏览器中打开", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }

    private var map: some View {
        Group {
            if let latitude = attachment.metadata.latitude,
               let longitude = attachment.metadata.longitude {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                    )
                ) {
                    Marker(
                        attachment.metadata.mapTitle ?? "地点",
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    )
                }
                .mapStyle(.standard)
            } else {
                ContentUnavailableView("无法读取地点", systemImage: "map")
            }
        }
    }
}

struct AudioAttachmentPlayer: View {
    let attachment: Attachment
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LumenTheme.accent)
            Text(attachment.ocrText.isEmpty ? "录音附件" : attachment.ocrText)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                toggle()
            } label: {
                Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .onDisappear { player?.stop() }
    }

    private func toggle() {
        if player == nil {
            do {
                player = try AVAudioPlayer(data: attachment.data)
                player?.prepareToPlay()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

struct LinkAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var title = ""
    let onAdd: (URL, String) -> Void

    private var parsedURL: URL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("链接") {
                    TextField("https://example.com", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("标题（可选）", text: $title)
                }
                Section {
                    Text("链接会作为富卡片嵌入正文，点击可在浏览器中打开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加网页链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if let parsedURL {
                            onAdd(parsedURL, title)
                            dismiss()
                        }
                    }
                    .disabled(parsedURL == nil)
                }
            }
        }
    }
}

struct MapAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var latitude = "37.3349"
    @State private var longitude = "-122.0090"
    let onAdd: (String, Double, Double) -> Void

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude), let lon = Double(longitude),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("地点") {
                    TextField("地点名称", text: $name)
                    TextField("纬度", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("经度", text: $longitude).keyboardType(.numbersAndPunctuation)
                }
                if let coordinate {
                    Section {
                        Map(
                            initialPosition: .region(
                                MKCoordinateRegion(
                                    center: coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                )
                            )
                        ) {
                            Marker(name.isEmpty ? "地点" : name, coordinate: coordinate)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .navigationTitle("添加地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if let coordinate {
                            onAdd(name.isEmpty ? "地点" : name, coordinate.latitude, coordinate.longitude)
                            dismiss()
                        }
                    }
                    .disabled(coordinate == nil)
                }
            }
        }
    }
}
