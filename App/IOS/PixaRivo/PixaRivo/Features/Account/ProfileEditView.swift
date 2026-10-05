import PhotosUI
import SwiftUI
import UIKit

enum PixaProfileEditMode: Equatable {
    case avatar
    case nickname
}

struct ProfileEditView: View {
    let mode: PixaProfileEditMode

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var profile: PixaAccountProfile?
    @State private var displayName = ""
    @State private var originalDisplayName = ""
    @State private var canChangeDisplayName = true
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var cropSourceImage: UIImage?
    @State private var showsAvatarCropper = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if mode == .avatar {
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        avatar
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(PixaTheme.accent, in: Circle())
                            .overlay { Circle().stroke(.white, lineWidth: 3) }
                            .offset(x: 2, y: 2)
                            .allowsHitTesting(false)
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Color.clear
                                .frame(width: 112, height: 112)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityLabel(Text("profile.change_avatar"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section {
                    Text("profile.avatar_hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if mode == .nickname {
                Section("profile.nickname") {
                    if canChangeDisplayName {
                        TextField("profile.nickname", text: $displayName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: displayName) { _, value in
                                if value.count > 40 { displayName = String(value.prefix(40)) }
                            }
                        Text("profile.nickname_once_hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayName)
                        Text("profile.nickname_used_hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PixaTheme.paper)
        .navigationTitle(
            mode == .avatar ? "profile.change_avatar" : "profile.change_nickname"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if mode == .avatar || canChangeDisplayName {
                    Button("profile.save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .overlay {
            if isLoading {
                PixaLoadingStateView(
                    title: "loading.account.title",
                    message: "loading.account.message",
                    minHeight: 180
                )
                .padding(24)
            }
        }
        .task { await load() }
        .onChange(of: selectedItem) { _, item in
            Task { await loadImage(item) }
        }
        .sheet(isPresented: $showsAvatarCropper, onDismiss: {
            cropSourceImage = nil
            selectedItem = nil
        }) {
            if let cropSourceImage {
                AvatarCropView(image: cropSourceImage) { croppedImage in
                    selectedImage = croppedImage
                    showsAvatarCropper = false
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 3) }
        } else {
            AccountAvatarView(
                userID: session.user?.id,
                url: resolvedAccountURL(profile?.avatarURL ?? session.user?.avatarURL),
                fallback: displayName.nilIfEmpty ?? session.user?.email,
                size: 104
            )
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await session.fetchProfile()
            profile = value
            displayName = value.displayName?.nilIfEmpty ?? session.user?.displayName ?? ""
            originalDisplayName = displayName
            canChangeDisplayName = value.canChangeDisplayName
        } catch {
            errorMessage = error.localizedDescription
            displayName = session.user?.displayName ?? ""
            originalDisplayName = displayName
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw APIError.rejected(AppLanguage.localized("profile.image_invalid"))
            }
            cropSourceImage = image
            showsAvatarCropper = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        let name = displayName.nilIfEmpty
        if mode == .nickname {
            guard canChangeDisplayName,
                  let name,
                  name != originalDisplayName else { return }
        } else {
            guard selectedImage != nil else { return }
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var avatarURL = profile?.avatarURL
            if let selectedImage {
                guard let data = selectedImage.profileJPEGData() else {
                    throw APIError.rejected(AppLanguage.localized("profile.image_invalid"))
                }
                avatarURL = try await session.uploadAvatar(data)
            }
            let updated = try await session.updateProfile(
                PixaUpdateProfileRequest(
                    displayName: mode == .nickname ? name : nil,
                    mobile: profile?.mobile,
                    companyName: profile?.companyName,
                    taxNo: profile?.taxNo,
                    avatarURL: avatarURL,
                    countryCode: profile?.countryCode
                )
            )
            if let selectedImage,
               let data = selectedImage.profileJPEGData(),
               let userID = session.user?.id {
                await PixaAvatarCache.shared.replace(data: data, userID: userID)
            }
            profile = updated
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canSave: Bool {
        guard !isSaving && !isLoading else { return false }
        switch mode {
        case .avatar:
            return selectedImage != nil
        case .nickname:
            guard canChangeDisplayName,
                  let name = displayName.nilIfEmpty else { return false }
            return name != originalDisplayName
        }
    }
}

private extension UIImage {
    func profileJPEGData(maximumDimension: CGFloat = 512) -> Data? {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let ratio = min(1, maximumDimension / max(pixelWidth, pixelHeight))
        let outputSize = CGSize(
            width: max(1, pixelWidth * ratio),
            height: max(1, pixelHeight * ratio)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            draw(in: CGRect(origin: .zero, size: outputSize))
        }
        return normalized.jpegData(compressionQuality: 0.82)
    }
}

private struct AvatarCropView: View {
    let image: UIImage
    let onComplete: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var settledOffset = CGSize.zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSize = min(proxy.size.width - 40, 380)
                VStack(spacing: 22) {
                    Spacer(minLength: 10)
                    cropCanvas(size: cropSize, showsGuide: true)
                        .frame(width: cropSize, height: cropSize)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(cropSize: cropSize))
                        .simultaneousGesture(magnificationGesture(cropSize: cropSize))
                        .accessibilityLabel(Text("profile.crop.accessibility"))

                    HStack(spacing: 14) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: Binding(
                            get: { zoom },
                            set: { value in
                                zoom = value
                                settledZoom = value
                                offset = clamped(offset, cropSize: cropSize, zoom: value)
                                settledOffset = offset
                            }
                        ), in: 1...5)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)

                    Text("profile.crop.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PixaTheme.paper.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("profile.crop.use") {
                            if let cropped = renderedCrop(size: cropSize) {
                                onComplete(cropped)
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("profile.crop.title")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cropCanvas(size: CGFloat, showsGuide: Bool) -> some View {
        ZStack {
            Color.black
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .scaleEffect(zoom)
                .offset(offset)
            if showsGuide {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 2)
                    .padding(3)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
    }

    private func dragGesture(cropSize: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                offset = clamped(proposed, cropSize: cropSize, zoom: zoom)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private func magnificationGesture(cropSize: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(5, max(1, settledZoom * value))
                offset = clamped(offset, cropSize: cropSize, zoom: zoom)
            }
            .onEnded { _ in
                settledZoom = zoom
                settledOffset = offset
            }
    }

    private func clamped(_ proposed: CGSize, cropSize: CGFloat, zoom: CGFloat) -> CGSize {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
        let ratio = pixelWidth / pixelHeight
        let baseWidth = ratio >= 1 ? cropSize * ratio : cropSize
        let baseHeight = ratio >= 1 ? cropSize : cropSize / ratio
        let maximumX = max(0, (baseWidth * zoom - cropSize) / 2)
        let maximumY = max(0, (baseHeight * zoom - cropSize) / 2)
        return CGSize(
            width: min(maximumX, max(-maximumX, proposed.width)),
            height: min(maximumY, max(-maximumY, proposed.height))
        )
    }

    @MainActor
    private func renderedCrop(size: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: cropCanvas(size: size, showsGuide: false))
        renderer.scale = 512 / size
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
