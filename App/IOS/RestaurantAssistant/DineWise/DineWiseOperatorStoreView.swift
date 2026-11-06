import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

struct DineWiseOperatorStoreView: View {
    let token: String

    @StateObject private var location = DineWiseLocationProvider()
    @State private var stores: [DineWiseOperatorStore] = []
    @State private var name = ""
    @State private var businessType = ""
    @State private var ownerEmail = ""
    @State private var address = ""
    @State private var introduction = ""
    @State private var payments: Set<String> = []
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var createdStoreID: String?
    @State private var creationKey: String?
    @State private var busy = false
    @State private var error = ""
    @State private var notice = ""

    private let api = DineWiseAPI()
    private let paymentOptions = [
        ("wechat_pay", "微信支付"), ("alipay", "支付宝"),
        ("cash", "现金"), ("bank_card", "银行卡"), ("other", "其他")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开设试用门店").font(.headline)
            Text("老板须先用邮箱验证码登录餐有数。门店创建后会授予该账号老板岗位。")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("门店名称", text: $name).onChange(of: name) { _, _ in resetRequest() }
            TextField("餐饮类型，例如火锅、中餐", text: $businessType)
                .onChange(of: businessType) { _, _ in resetRequest() }
            TextField("老板已验证邮箱", text: $ownerEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .onChange(of: ownerEmail) { _, _ in resetRequest() }
            TextField("门店地址", text: $address)
                .onChange(of: address) { _, _ in resetRequest() }
            Button("使用当前位置") {
                location.request()
                resetRequest()
            }
            if let latitude = location.latitude, let longitude = location.longitude {
                Text("定位：\(latitude, specifier: "%.6f"), \(longitude, specifier: "%.6f")")
                    .font(.footnote)
                Button("清除定位，仅保留手填地址") { location.clear(); resetRequest() }
            }
            if !location.error.isEmpty {
                Text("\(location.error)；可手填地址继续开店。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            TextField("门店介绍", text: $introduction, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: introduction) { _, _ in resetRequest() }
            Text("顾客可用支付方式").font(.subheadline.bold())
            ForEach(paymentOptions, id: \.0) { option in
                Toggle(option.1, isOn: Binding(
                    get: { payments.contains(option.0) },
                    set: { enabled in
                        if enabled { payments.insert(option.0) } else { payments.remove(option.0) }
                        resetRequest()
                    }
                ))
            }
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 180)
            }
            HStack {
                Button("拍门店照片") { showCamera = true }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker("从相册选择", selection: $photoItem, matching: .images)
            }
            .sheet(isPresented: $showCamera) {
                DineWiseCameraPicker { image in photo = image; resetDraftKey() }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photo = image
                        resetDraftKey()
                    }
                }
            }
            Button("创建并绑定老板") { createStore() }
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                    || businessType.trimmingCharacters(in: .whitespaces).isEmpty
                    || ownerEmail.trimmingCharacters(in: .whitespaces).isEmpty
                    || address.trimmingCharacters(in: .whitespaces).isEmpty || payments.isEmpty)
            if let createdStoreID, let photo {
                Button("为已创建门店上传照片") { uploadPhoto(photo, storeID: createdStoreID) }
                    .disabled(busy)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if !notice.isEmpty { Text(notice).foregroundStyle(.green) }
            if !stores.isEmpty {
                Text("我开设的门店").font(.headline)
                ForEach(stores) { store in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.Name).font(.subheadline.bold())
                        Text("\(store.BusinessType) · \(store.Address)")
                        Text("老板：\(store.OwnerEmail) · \(store.HasPhoto ? "已上传照片" : "未上传照片")")
                    }
                    .font(.footnote)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .task {
            do { stores = try await api.operatorStores(token: token) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func resetRequest() {
        creationKey = nil
        createdStoreID = nil
    }

    private func resetDraftKey() {
        creationKey = nil
    }

    private func createStore() {
        busy = true
        error = ""
        notice = ""
        let key = creationKey ?? UUID().uuidString
        creationKey = key
        Task {
            defer { busy = false }
            do {
                let store = try await api.operatorCreateStore(
                    token: token, name: name.trimmingCharacters(in: .whitespaces),
                    businessType: businessType.trimmingCharacters(in: .whitespaces),
                    ownerEmail: ownerEmail.trimmingCharacters(in: .whitespaces).lowercased(),
                    address: address.trimmingCharacters(in: .whitespaces),
                    introduction: introduction.trimmingCharacters(in: .whitespaces),
                    paymentMethods: Array(payments).sorted(), latitude: location.latitude,
                    longitude: location.longitude, idempotencyKey: key)
                createdStoreID = store.Id
                stores = try await api.operatorStores(token: token)
                if let photo { uploadPhoto(photo, storeID: store.Id) }
                else { notice = "门店已创建并绑定老板，可继续上传照片。" }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func uploadPhoto(_ image: UIImage, storeID: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            error = "照片无法转换为 JPEG。"
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await api.operatorUploadPhoto(token: token, storeID: storeID, data: data)
                stores = try await api.operatorStores(token: token)
                notice = "门店与照片已保存。"
                error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
}

private final class DineWiseLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var error = ""
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        error = ""
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: error = "未取得定位权限"
        }
    }

    func clear() {
        latitude = nil
        longitude = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        error = ""
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = "定位失败"
    }
}

private struct DineWiseCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
