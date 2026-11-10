import CoreLocation
import CryptoKit
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct DineWiseOperatorBusinessHoursPeriod: Identifiable {
    let id = UUID()
    var opensAt: Date
    var closesAt: Date
}

func decodeDineWiseStorePhoto(_ source: Data) throws -> UIImage {
    guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2200,
            kCGImageSourceCreateThumbnailWithTransform: true
          ] as CFDictionary) else {
        throw DineWiseAPIError.failed("无法读取所选门店照片。")
    }
    return UIImage(cgImage: cgImage)
}

func compressedDineWiseStorePhotoData(_ image: UIImage) throws -> Data {
    let sourceWidth = Int(image.size.width * image.scale)
    let sourceHeight = Int(image.size.height * image.scale)
    guard sourceWidth > 0, sourceHeight > 0 else {
        throw DineWiseAPIError.failed("门店照片尺寸无效。")
    }

    var maxDimension = max(sourceWidth, sourceHeight)
    var outputImage = image
    let rendererFormat = UIGraphicsImageRendererFormat.default()
    rendererFormat.scale = 1
    rendererFormat.opaque = true
    while true {
        let scale = min(1, 2200.0 / Double(maxDimension))
        let width = max(1, Int(Double(sourceWidth) * scale))
        let height = max(1, Int(Double(sourceHeight) * scale))
        if outputImage === image || outputImage.cgImage?.width != width
            || outputImage.cgImage?.height != height {
            outputImage = UIGraphicsImageRenderer(
                size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: rendererFormat
            ).image { _ in image.draw(in: CGRect(x: 0, y: 0,
                width: CGFloat(width), height: CGFloat(height))) }
        }

        var quality: CGFloat = 0.88
        while true {
            guard let data = outputImage.jpegData(compressionQuality: quality) else {
                throw DineWiseAPIError.failed("门店照片无法转换为 JPEG。")
            }
            if data.count <= 5 * 1024 * 1024 { return data }
            if quality > 0.4 {
                quality = max(0.4, quality - 0.08)
                continue
            }
            guard maxDimension > 640 else {
                throw DineWiseAPIError.failed("门店照片压缩后仍超过 5 MB，请选择较小的图片。")
            }
            maxDimension = max(640, Int(Double(maxDimension) * 0.75))
            break
        }
    }
}

struct DineWiseOperatorStoreView: View {
    @Environment(\.colorScheme) private var colorScheme
    let token: String

    @StateObject private var location = DineWiseLocationProvider()
    @State private var stores: [DineWiseOperatorStore] = []
    @State private var hasOlderStores = false
    @State private var name = ""
    @State private var businessType = ""
    @State private var ownerEmail = ""
    @State private var address = ""
    @State private var introduction = ""
    @State private var payments: Set<String> = []
    @State private var cutoffMinutes = 0
    @State private var businessHours = Array(repeating: [DineWiseOperatorBusinessHoursPeriod](), count: 7)
    @State private var expandedBusinessDay: Int?
    @State private var scheduleExpanded = false
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var locationTokenGeneration: Int?
    @State private var createdStoreID: String?
    @State private var creationKey: String?
    @State private var busy = false
    @State private var error = ""
    @State private var notice = ""
    @State private var activeToken = ""
    @State private var tokenGeneration = 0
    @State private var cameraTokenGeneration = 0

    private let api = DineWiseAPI()
    private let paymentOptions = [
        ("wechat_pay", "微信支付"), ("alipay", "支付宝"),
        ("cash", "现金"), ("bank_card", "银行卡"), ("other", "其他")
    ]

    private var authorizedLocation: (latitude: Double, longitude: Double)? {
        guard locationTokenGeneration == tokenGeneration,
              let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return (latitude, longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开设试用门店").font(.headline)
            Text("老板账号须已由管理员开通。门店创建后会授予该账号老板岗位。")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("门店名称", text: $name).onChange(of: name) { _, _ in resetRequest() }
            TextField("餐饮类型，例如火锅、中餐", text: $businessType)
                .onChange(of: businessType) { _, _ in resetRequest() }
            TextField("老板用户名或已验证邮箱", text: $ownerEmail)
                .textInputAutocapitalization(.never)
                .onChange(of: ownerEmail) { _, _ in resetRequest() }
            TextField("门店地址", text: $address)
                .onChange(of: address) { _, _ in resetRequest() }
            Button("使用当前位置") {
                locationTokenGeneration = tokenGeneration
                location.request()
                resetRequest()
            }
            if let authorizedLocation {
                let latitude = authorizedLocation.latitude
                let longitude = authorizedLocation.longitude
                Text("定位：\(latitude, specifier: "%.6f"), \(longitude, specifier: "%.6f")")
                    .font(.footnote)
                Button("清除定位，仅保留手填地址") {
                    locationTokenGeneration = nil
                    location.clear()
                    resetRequest()
                }
            }
            if locationTokenGeneration == tokenGeneration && !location.error.isEmpty {
                Text("\(location.error)；可手填地址继续开店。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            TextField("门店介绍", text: $introduction, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: introduction) { _, _ in resetRequest() }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { scheduleExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("每周营业时段").font(.subheadline.weight(.semibold))
                        Text(scheduleSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: scheduleExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(scheduleExpanded ? "已展开" : "已收起")
            .accessibilityHint(scheduleExpanded ? "双击收起营业时段" : "双击展开营业时段")
            if scheduleExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("新门店营业日期默认使用此设备的系统时区。每天最多 4 段；打烊早于开门表示次日打烊，时段不能重叠。")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("全周连续营业") {
                                applyBusinessHoursWeekPreset(periods: ["09:00-22:00"])
                            }
                            .buttonStyle(.bordered)
                            Button("全周午晚市") {
                                applyBusinessHoursWeekPreset(periods: ["09:00-14:00", "17:00-22:00"])
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("全周早午晚市") {
                            applyBusinessHoursWeekPreset(periods: ["07:00-10:00", "11:00-14:00", "17:00-22:00"])
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("快速设置整周后，点选日期可查看摘要或展开调整。")
                        .font(.caption).foregroundStyle(.secondary)
                    DineWiseDateTimePickerField(title: "营业日切分时间", selection: Binding(
                        get: { dateForTime(String(format: "%02d:%02d", cutoffMinutes / 60, cutoffMinutes % 60)) },
                        set: { value in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                            cutoffMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                            resetRequest()
                        }), displayedComponents: .hourAndMinute)
                    Text("每天从此时间开始计入新的营业日。")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(dineWiseWeekdays.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedBusinessDay = expandedBusinessDay == index ? nil : index
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(dineWiseWeekdays[index]).font(.subheadline.weight(.semibold))
                                        Text(businessHoursDaySummary(index))
                                            .font(.footnote).foregroundStyle(.secondary)
                                            .lineLimit(1).minimumScaleFactor(0.75)
                                        Spacer(minLength: 4)
                                        Image(systemName: expandedBusinessDay == index ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DineWiseTheme.accent(for: colorScheme))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(dineWiseWeekdays[index])，\(businessHoursDaySummary(index))")
                                .accessibilityValue(expandedBusinessDay == index ? "已展开" : "已收起")
                                .accessibilityHint("双击\(expandedBusinessDay == index ? "收起" : "展开")此日营业时段")
                                Spacer()
                                Toggle("营业", isOn: Binding(
                                    get: { !businessHours[index].isEmpty },
                                    set: { isOpen in
                                        if isOpen {
                                            if businessHours[index].isEmpty { addBusinessPeriod(dayIndex: index) }
                                            expandedBusinessDay = index
                                        } else {
                                            businessHours[index] = []
                                            if expandedBusinessDay == index { expandedBusinessDay = nil }
                                            resetRequest()
                                        }
                                    }))
                                .labelsHidden()
                                .accessibilityLabel("\(dineWiseWeekdays[index])营业状态")
                                .accessibilityValue(businessHours[index].isEmpty ? "休息" : "营业")
                                .accessibilityHint("双击切换该日是否营业")
                            }
                            if expandedBusinessDay == index {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Button("连续营业") {
                                            applyBusinessHoursPreset(dayIndex: index, periods: ["09:00-22:00"])
                                        }
                                        .buttonStyle(.bordered)
                                        .accessibilityHint("用常用连续营业时段替换\(dineWiseWeekdays[index])设置")
                                        Button("午晚市") {
                                            applyBusinessHoursPreset(dayIndex: index,
                                                periods: ["09:00-14:00", "17:00-22:00"])
                                        }
                                        .buttonStyle(.bordered)
                                        .accessibilityHint("用午晚市时段替换\(dineWiseWeekdays[index])设置")
                                    }
                                    Button("早午晚市") {
                                        applyBusinessHoursPreset(dayIndex: index,
                                            periods: ["07:00-10:00", "11:00-14:00", "17:00-22:00"])
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityHint("用早午晚市时段替换\(dineWiseWeekdays[index])设置")
                                    Text("快捷替换当天").font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(businessHours[index]) { period in
                                    let periodNumber = (businessHours[index].firstIndex(where: { $0.id == period.id }) ?? 0) + 1
                                    HStack(spacing: 8) {
                                        DineWiseDateTimePickerField(title: "开门",
                                            accessibilityTitle: "\(dineWiseWeekdays[index])时段\(periodNumber)开门时间",
                                            selection: Binding(
                                                get: { businessPeriod(id: period.id, dayIndex: index)?.opensAt ?? period.opensAt },
                                                set: { updateBusinessPeriod(id: period.id, dayIndex: index, opensAt: $0) }),
                                            displayedComponents: .hourAndMinute,
                                            quickTimes: ["07:00", "08:00", "09:00", "10:00", "11:00", "17:00",
                                                         "06:00", "08:30", "09:30", "12:00", "14:00", "16:00",
                                                         "18:00", "19:00"],
                                            validationMessage: { businessHoursValidationMessage(
                                                id: period.id, dayIndex: index, opensAt: $0) })
                                            .frame(maxWidth: .infinity)
                                        DineWiseDateTimePickerField(title: "打烊",
                                                accessibilityTitle: "\(dineWiseWeekdays[index])时段\(periodNumber)打烊时间",
                                                selection: Binding(
                                                    get: { businessPeriod(id: period.id, dayIndex: index)?.closesAt ?? period.closesAt },
                                                    set: { updateBusinessPeriod(id: period.id, dayIndex: index, closesAt: $0) }),
                                                displayedComponents: .hourAndMinute,
                                                    quickTimes: ["14:00", "17:00", "18:00", "21:00", "22:00", "23:00",
                                                                 "12:00", "13:00", "14:30", "15:00", "16:00", "19:00",
                                                                 "20:00", "22:30"],
                                                validationMessage: { businessHoursValidationMessage(
                                                    id: period.id, dayIndex: index, closesAt: $0) })
                                            .frame(maxWidth: .infinity)
                                        Button("移除时段", systemImage: "minus.circle", role: .destructive) {
                                            removeBusinessPeriod(id: period.id, dayIndex: index)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(8)
                                    .background(DineWiseTheme.inset,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                if !businessHours[index].isEmpty, businessHours[index].count < 4 {
                                    Button("添加时段", systemImage: "plus.circle") {
                                        addBusinessPeriod(dayIndex: index)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
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
                Button("拍门店照片") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        error = "当前设备不支持相机拍摄，请从相册选择照片。"
                        return
                    }
                    cameraTokenGeneration = tokenGeneration
                    showCamera = true
                }
                PhotosPicker("从相册选择", selection: $photoItem, matching: .images)
            }
            .sheet(isPresented: $showCamera) {
                DineWiseCameraPicker { image in
                    guard cameraTokenGeneration == tokenGeneration else { return }
                    photo = image
                    resetDraftKey()
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                let requestToken = token
                let generation = tokenGeneration
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = try? decodeDineWiseStorePhoto(data),
                       isCurrentToken(requestToken, generation: generation) {
                        photo = image
                        resetDraftKey()
                    } else if isCurrentToken(requestToken, generation: generation) {
                        error = "无法读取所选门店照片。"
                    }
                }
            }
            Button("创建并绑定老板") { createStore() }
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                    || businessType.trimmingCharacters(in: .whitespaces).isEmpty
                    || ownerEmail.trimmingCharacters(in: .whitespaces).isEmpty
                    || address.trimmingCharacters(in: .whitespaces).isEmpty || payments.isEmpty
                    || (createdStoreID != nil && photo != nil))
            if createdStoreID != nil && photo != nil {
                Text("请先为已创建门店完成照片上传，再开设下一家门店。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let createdStoreID, let photo {
                Button("为已创建门店上传照片") { uploadPhoto(photo, storeID: createdStoreID) }
                    .disabled(busy)
            }
            if !error.isEmpty { Text(error).foregroundStyle(DineWiseTheme.danger(for: colorScheme)) }
            if !notice.isEmpty {
                Text(notice).foregroundStyle(DineWiseTheme.accent(for: colorScheme))
            }
            HStack {
                Text("我开设的门店").font(.headline)
                Spacer()
                Button("刷新门店列表") { refreshStores() }
                    .disabled(busy)
            }
            if !stores.isEmpty {
                ForEach(stores) { store in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.Name).font(.subheadline.bold())
                        Text("\(store.BusinessType) · \(store.Address)")
                        Text("每周营业：\(dineWiseBusinessHoursSummary(store.BusinessHours))")
                        Text("老板：\(store.OwnerUsername ?? store.OwnerEmail) · \(store.HasPhoto ? "已上传照片" : "未上传照片")")
                    }
                    .font(.footnote)
                }
                if hasOlderStores {
                    Button(busy ? "正在读取…" : "加载更早的门店") { loadOlderStores() }
                        .buttonStyle(.bordered).disabled(busy)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(busy)
        .task(id: token) {
            tokenGeneration += 1
            activeToken = token
            let generation = tokenGeneration
            stores = []; hasOlderStores = false; name = ""; businessType = ""; ownerEmail = ""
            address = ""; introduction = ""; payments = []
            businessHours = Array(repeating: [], count: 7); scheduleExpanded = false
            expandedBusinessDay = nil
            photo = nil; photoItem = nil; createdStoreID = nil; creationKey = nil
            showCamera = false; cameraTokenGeneration = generation
            locationTokenGeneration = nil
            location.clear(); location.error = ""
            busy = false; error = ""; notice = ""
            do {
                let result = try await api.operatorStores(token: token)
                guard isCurrentToken(token, generation: generation) else { return }
                stores = result
                hasOlderStores = result.count >= 100
            } catch {
                guard isCurrentToken(token, generation: generation) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func resetRequest() {
        creationKey = nil
    }

    private func resetDraftKey() {
        creationKey = nil
    }

    private func createStore() {
        let hoursText = businessHours.map { day in
            day.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }.joined(separator: ", ")
        }
        guard let hours = dineWiseBusinessHoursPayload(hoursText) else {
            error = "请检查营业时段：每天最多 4 段，开门和打烊时间不能相同，且各时段不能重叠。"
            return
        }
        busy = true
        error = ""
        notice = ""
        let key = creationKey ?? UUID().uuidString
        creationKey = key
        let requestToken = token
        let generation = tokenGeneration
        let requestName = name.trimmingCharacters(in: .whitespaces)
        let requestBusinessType = businessType.trimmingCharacters(in: .whitespaces)
        let requestOwnerEmail = ownerEmail.trimmingCharacters(in: .whitespaces).lowercased()
        let requestAddress = address.trimmingCharacters(in: .whitespaces)
        let requestIntroduction = introduction.trimmingCharacters(in: .whitespaces)
        let requestPayments = Array(payments).sorted()
        let requestLocation = authorizedLocation
        let requestCutoffMinutes = cutoffMinutes
        let requestPhoto = photo
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            let store: DineWiseOperatorStore
            do {
                store = try await api.operatorCreateStore(
                    token: requestToken, name: requestName, businessType: requestBusinessType,
                    ownerEmail: requestOwnerEmail, address: requestAddress,
                    introduction: requestIntroduction, paymentMethods: requestPayments,
                    latitude: requestLocation?.latitude, longitude: requestLocation?.longitude,
                    businessHours: hours, cutoffMinutes: requestCutoffMinutes,
                    idempotencyKey: key)
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                self.error = "创建门店失败：\(error.localizedDescription)"
                return
            }
            guard isCurrentToken(requestToken, generation: generation) else { return }
            createdStoreID = store.Id
            notice = "门店已创建并绑定老板。"
            if let requestPhoto {
                do {
                    let data = try compressedDineWiseStorePhotoData(requestPhoto)
                    _ = try await api.operatorUploadPhoto(token: requestToken,
                        storeID: store.Id, data: data)
                    createdStoreID = nil
                    self.photo = nil
                    photoItem = nil
                } catch {
                    guard isCurrentToken(requestToken, generation: generation) else { return }
                    self.error = "门店已创建并绑定老板，但照片上传失败；可点击“为已创建门店上传照片”重试。\(error.localizedDescription)"
                    return
                }
                guard isCurrentToken(requestToken, generation: generation) else { return }
            }
            do {
                let refreshedStores = try await api.operatorStores(token: requestToken)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                stores = refreshedStores
                hasOlderStores = refreshedStores.count >= 100
                notice = requestPhoto == nil ? "门店已创建并绑定老板。" : "门店与照片已保存。"
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                self.error = "门店已创建\(requestPhoto == nil ? "" : "，照片已上传")，但列表刷新失败；可点击“刷新门店列表”重试。\(error.localizedDescription)"
            }
        }
    }

    private func uploadPhoto(_ image: UIImage, storeID: String) {
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        error = ""
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let data = try compressedDineWiseStorePhotoData(image)
                _ = try await api.operatorUploadPhoto(token: requestToken,
                    storeID: storeID, data: data)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                if createdStoreID == storeID {
                    createdStoreID = nil
                    photo = nil
                    photoItem = nil
                }
                notice = "门店照片已上传。"
                do {
                    let refreshedStores = try await api.operatorStores(token: requestToken)
                    guard isCurrentToken(requestToken, generation: generation) else { return }
                    stores = refreshedStores
                    hasOlderStores = refreshedStores.count >= 100
                    notice = "门店与照片已保存。"
                    error = ""
                } catch {
                    guard isCurrentToken(requestToken, generation: generation) else { return }
                    self.error = "照片已上传，但门店列表刷新失败；可点击“刷新门店列表”重试。\(error.localizedDescription)"
                }
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                self.error = "门店照片上传失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshStores() {
        guard !busy else { return }
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        error = ""
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let refreshedStores = try await api.operatorStores(token: requestToken)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                stores = refreshedStores
                hasOlderStores = refreshedStores.count >= 100
                notice = "门店列表已刷新。"
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                self.error = "门店列表刷新失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadOlderStores() {
        guard !busy, hasOlderStores, let cursor = stores.last?.Id else { return }
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        error = ""
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let older = try await api.operatorStores(token: requestToken, beforeID: cursor)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                let existing = Set(stores.map(\.Id))
                stores.append(contentsOf: older.filter { !existing.contains($0.Id) })
                hasOlderStores = older.count >= 100
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private var scheduleSummary: String {
        let configuredDays = businessHours.filter { !$0.isEmpty }.count
        let time = String(format: "%02d:%02d", cutoffMinutes / 60, cutoffMinutes % 60)
        return configuredDays == 0 ? "暂不填写 · 系统时区 · 切分 \(time)"
            : "已配置 \(configuredDays) 天 · 系统时区 · 切分 \(time)"
    }

    private func businessHoursDaySummary(_ index: Int) -> String {
        let periods = businessHours[index]
        guard !periods.isEmpty else { return "休息" }
        return periods.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }
            .joined(separator: " · ")
    }

    private func businessPeriod(id: UUID, dayIndex: Int) -> DineWiseOperatorBusinessHoursPeriod? {
        businessHours[dayIndex].first { $0.id == id }
    }

    private func businessHoursValidationMessage(id: UUID, dayIndex: Int,
                                                opensAt: Date? = nil,
                                                closesAt: Date? = nil) -> String? {
        guard let periodIndex = businessHours[dayIndex].firstIndex(where: { $0.id == id }) else {
            return "该营业时段已变化，请重新选择。"
        }
        var candidate = businessHours.map { day in
            day.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }
                .joined(separator: ", ")
        }
        var periods = businessHours[dayIndex]
        if let opensAt { periods[periodIndex].opensAt = opensAt }
        if let closesAt { periods[periodIndex].closesAt = closesAt }
        candidate[dayIndex] = periods.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }
            .joined(separator: ", ")
        return dineWiseBusinessHoursPayload(candidate) == nil
            ? "与其他营业时段冲突，请调整时间后重试。" : nil
    }

    private func updateBusinessPeriod(id: UUID, dayIndex: Int, opensAt: Date? = nil, closesAt: Date? = nil) {
        guard let periodIndex = businessHours[dayIndex].firstIndex(where: { $0.id == id }) else { return }
        if let opensAt { businessHours[dayIndex][periodIndex].opensAt = opensAt }
        if let closesAt { businessHours[dayIndex][periodIndex].closesAt = closesAt }
        resetRequest()
    }

    private func removeBusinessPeriod(id: UUID, dayIndex: Int) {
        businessHours[dayIndex].removeAll { $0.id == id }
        resetRequest()
    }

    private func applyBusinessHoursPreset(dayIndex: Int, periods: [String]) {
        let current = businessHours.map { day in
            day.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }
                .joined(separator: ", ")
        }
        let candidate = current.enumerated().map { index, value in
            index == dayIndex ? periods.joined(separator: ", ") : value
        }
        guard dineWiseBusinessHoursPayload(candidate) != nil else {
            error = "该快捷时段与相邻营业日冲突，请先调整相关时段。"
            return
        }
        businessHours[dayIndex] = periods.compactMap { value in
            let pair = value.split(separator: "-", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return DineWiseOperatorBusinessHoursPeriod(
                opensAt: dateForTime(pair[0]), closesAt: dateForTime(pair[1]))
        }
        resetRequest()
        error = ""
    }

    private func applyBusinessHoursWeekPreset(periods: [String]) {
        let day = periods.joined(separator: ", ")
        let candidate = Array(repeating: day, count: 7)
        guard dineWiseBusinessHoursPayload(candidate) != nil else {
            error = "该快捷时段与营业日规则冲突，请先调整时段。"
            return
        }
        businessHours = Array(repeating: periods.map { value in
            let pair = value.split(separator: "-", maxSplits: 1).map(String.init)
            return DineWiseOperatorBusinessHoursPeriod(
                opensAt: dateForTime(pair[0]), closesAt: dateForTime(pair[1]))
        }, count: 7)
        resetRequest()
        error = ""
    }

    private func addBusinessPeriod(dayIndex: Int) {
        guard businessHours[dayIndex].count < 4 else { return }
        let candidates = businessHours[dayIndex].isEmpty
            ? [("09:00", "22:00"), ("09:00", "14:00"), ("17:00", "23:00"), ("00:00", "06:00"), ("06:00", "09:00")]
            : [("17:00", "23:00"), ("09:00", "14:00"), ("00:00", "06:00"), ("06:00", "09:00"), ("14:00", "17:00"), ("09:00", "22:00")]
        for (opensAt, closesAt) in candidates {
            var candidate = businessHours
            candidate[dayIndex].append(DineWiseOperatorBusinessHoursPeriod(
                opensAt: dateForTime(opensAt), closesAt: dateForTime(closesAt)))
            let candidateText = candidate.map { day in
                day.map { "\(timeString($0.opensAt))-\(timeString($0.closesAt))" }.joined(separator: ", ")
            }
            guard dineWiseBusinessHoursPayload(candidateText) != nil else { continue }
            businessHours = candidate
            resetRequest()
            return
        }
        error = "该营业日没有可添加的不重叠时段，请先调整已有时段。"
    }

    private func dateForTime(_ value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return Date(timeIntervalSince1970: 0) }
        var components = DateComponents()
        components.year = 2001; components.month = 1; components.day = 1
        components.hour = parts[0]; components.minute = parts[1]
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func timeString(_ value: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: value)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func isCurrentToken(_ requestToken: String, generation: Int) -> Bool {
        activeToken == requestToken && token == requestToken && tokenGeneration == generation
    }
}

struct DineWiseOperatorChargeView: View {
    let token: String
    let operatorID: String
    @State private var stores: [DineWiseOperatorStore] = []
    @State private var hasOlderStores = false
    @State private var charges: [DineWiseOperatorCharge] = []
    @State private var hasOlderCharges = false
    @State private var storeID = ""
    @State private var customerLabel = ""
    @State private var channel = "wechat"
    @State private var amount = ""
    @State private var paidAt = Date()
    @State private var voucherReference = ""
    @State private var note = ""
    @State private var busy = false
    @State private var feedback = ""
    @State private var showVoucherPicker = false
    @State private var showVoucherPDFPicker = false
    @State private var voucherPhoto: PhotosPickerItem?
    @State private var voucherTargetChargeID: String?
    @State private var activeToken = ""
    @State private var tokenGeneration = 0
    private let api = DineWiseAPI()
    private let channels = [
        ("wechat", "微信"), ("alipay", "支付宝"), ("cash", "现金"),
        ("bank_transfer", "银行转账"), ("other", "其他")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("仅登记运营人员已经收取的服务费。提交后待管理员核对，不代表线上支付成功。")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("关联门店", selection: $storeID) {
                Text("未开店，按客户登记").tag("")
                ForEach(stores) { store in Text(store.Name).tag(store.Id) }
            }
            if hasOlderStores {
                Button(busy ? "正在读取…" : "加载更早的门店") { loadOlderStores() }
                    .buttonStyle(.bordered).disabled(busy)
            }
            if storeID.isEmpty {
                TextField("客户称呼", text: $customerLabel)
            }
            Picker("实际收款渠道", selection: $channel) {
                ForEach(channels, id: \.0) { item in Text(item.1).tag(item.0) }
            }
            TextField("已收金额（元）", text: $amount)
                .keyboardType(.decimalPad)
            DineWiseDateTimePickerField(title: "实际收款时间", selection: $paidAt,
                displayedComponents: [.date, .hourAndMinute], maximumDate: Date())
            TextField(channel == "cash" ? "凭证单号或描述" : "交易单号或凭证描述",
                text: $voucherReference)
            if channel != "cash" {
                Text("非现金收款需要交易核对线索，普通备注不能替代。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            TextField("备注", text: $note, axis: .vertical)
                .lineLimit(2...4)
            Button(busy ? "正在登记…" : "提交待核对记录") { create() }
                .disabled(busy || amount.isEmpty || (storeID.isEmpty
                    && customerLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                    || (channel == "cash"
                        ? (voucherReference.trimmingCharacters(in: .whitespaces).isEmpty
                            && note.trimmingCharacters(in: .whitespaces).isEmpty)
                        : voucherReference.trimmingCharacters(in: .whitespaces).isEmpty))
            if !feedback.isEmpty { Text(feedback).font(.footnote) }
            HStack {
                Text("我的登记记录").font(.subheadline.bold())
                Spacer()
                Button(busy ? "正在刷新…" : "刷新") { refreshCharges() }
                    .disabled(busy)
            }
            if charges.isEmpty {
                Text("暂无收费记录").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(charges) { charge in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(charge.StoreName ?? charge.CustomerLabel ?? "客户") · ¥\(charge.AmountFen / 100).\(String(format: "%02lld", charge.AmountFen % 100))")
                            .font(.subheadline.bold())
                        Text("\(channelName(charge.Channel)) · \(statusName(charge.Status))")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let reason = charge.ReviewReason, !reason.isEmpty {
                            Text("审核备注：\(reason)").font(.footnote)
                        }
                        if charge.HasVoucherFile == true {
                            Text("已附凭证：\(charge.VoucherFileName ?? "图片")")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if charge.Status == "pending_review" {
                            Menu("上传收费凭证") {
                                Button("从相册选择图片", systemImage: "photo") {
                                    voucherTargetChargeID = charge.Id
                                    showVoucherPicker = true
                                }
                                Button("选择 PDF 文件", systemImage: "doc") {
                                    voucherTargetChargeID = charge.Id
                                    showVoucherPDFPicker = true
                                }
                            }
                            .disabled(busy)
                        }
                    }
                }
            }
            if hasOlderCharges {
                Button(busy ? "正在读取…" : "加载更早的收费记录") { loadOlderCharges() }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(busy)
        .photosPicker(isPresented: $showVoucherPicker, selection: $voucherPhoto, matching: .images)
        .onChange(of: voucherPhoto) { _, item in
            guard let item, let chargeID = voucherTargetChargeID else { return }
            voucherPhoto = nil
            Task { await uploadVoucher(item, chargeID: chargeID) }
        }
        .fileImporter(isPresented: $showVoucherPDFPicker,
            allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                guard let chargeID = voucherTargetChargeID else { return }
                importVoucherPDF(result, chargeID: chargeID)
            }
        .task(id: token) {
            tokenGeneration += 1
            activeToken = token
            let generation = tokenGeneration
            stores = []; hasOlderStores = false; charges = []; hasOlderCharges = false
            storeID = ""; customerLabel = ""
            channel = "wechat"; amount = ""; paidAt = Date()
            voucherReference = ""; note = ""
            busy = false; feedback = ""
            voucherPhoto = nil; voucherTargetChargeID = nil
            showVoucherPicker = false; showVoucherPDFPicker = false
            await refresh(token: token, generation: generation)
        }
    }

    private func uploadVoucher(_ item: PhotosPickerItem, chargeID: String) async {
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        feedback = "正在上传收费凭证…"
        defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
        do {
            guard let source = try await item.loadTransferable(type: Data.self),
                  let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2200,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else {
                throw DineWiseAPIError.failed("无法读取所选图片。")
            }
            let image = UIImage(cgImage: cgImage)
            var quality: CGFloat = 0.88
            var data = image.jpegData(compressionQuality: quality)
            while let current = data, current.count > 10 * 1024 * 1024, quality > 0.3 {
                quality -= 0.1
                data = image.jpegData(compressionQuality: quality)
            }
            guard let data, data.count <= 10 * 1024 * 1024 else {
                throw DineWiseAPIError.failed("图片压缩后仍超过 10 MB，请选择较小的图片。")
            }
            guard isCurrentToken(requestToken, generation: generation) else { return }
            try await uploadVoucherFile(data, fileName: "voucher.jpg",
                mimeType: "image/jpeg", chargeID: chargeID,
                token: requestToken, generation: generation)
        } catch {
            guard isCurrentToken(requestToken, generation: generation) else { return }
            feedback = error.localizedDescription + "；可重新选择同一图片重试。"
        }
    }

    private func importVoucherPDF(_ result: Result<[URL], Error>, chargeID: String) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                feedback = error.localizedDescription
            }
            return
        }
        let requestToken = token
        let generation = tokenGeneration
        Task {
            busy = true
            feedback = "正在读取收费凭证…"
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var data = Data()
                    while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                        guard data.count + chunk.count <= 10 * 1024 * 1024 else {
                            throw DineWiseAPIError.failed("PDF 凭证大小须在 10 MB 以内。")
                        }
                        data.append(chunk)
                    }
                    return data
                }.value
                guard data.count > 0, data.starts(with: Data("%PDF-".utf8)) else {
                    throw DineWiseAPIError.failed("所选文件不是有效的 PDF 凭证。")
                }
                guard isCurrentToken(requestToken, generation: generation) else { return }
                try await uploadVoucherFile(data, fileName: "voucher.pdf",
                    mimeType: "application/pdf", chargeID: chargeID,
                    token: requestToken, generation: generation)
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                feedback = error.localizedDescription + "；可重新选择文件重试。"
            }
        }
    }

    private func uploadVoucherFile(_ data: Data, fileName: String, mimeType: String,
                                   chargeID: String, token requestToken: String,
                                   generation: Int) async throws {
        guard data.count <= 10 * 1024 * 1024 else {
            throw DineWiseAPIError.failed("收费凭证不能超过 10 MB。")
        }
        let keyMaterial = Data("\(chargeID):\(fileName):\(mimeType):".utf8) + data
        let key = SHA256.hash(data: keyMaterial).map { String(format: "%02x", $0) }.joined()
        feedback = "正在上传收费凭证…"
        let uploaded = try await api.operatorUploadChargeVoucher(token: requestToken, chargeID: chargeID,
            fileName: fileName, mimeType: mimeType, data: data, idempotencyKey: key)
        guard isCurrentToken(requestToken, generation: generation) else { return }
        if let index = charges.firstIndex(where: { $0.Id == uploaded.Id }) {
            charges[index] = uploaded
        } else {
            charges.insert(uploaded, at: 0)
        }
        feedback = "收费凭证已上传，等待管理员核对。"
        do {
            let refreshed = try await api.operatorCharges(token: requestToken)
            guard isCurrentToken(requestToken, generation: generation) else { return }
            charges = refreshed
            hasOlderCharges = refreshed.count >= 100
        } catch {
            guard isCurrentToken(requestToken, generation: generation) else { return }
            feedback = "收费凭证已上传，但记录刷新失败；可点“刷新”重试。"
        }
    }

    private func refreshCharges() {
        guard !busy else { return }
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let refreshed = try await api.operatorCharges(token: requestToken)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                charges = refreshed
                hasOlderCharges = refreshed.count >= 100
                feedback = "收费记录已刷新。"
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                feedback = "收费记录刷新失败：\(error.localizedDescription)"
            }
        }
    }

    private func create() {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#,
                            options: .regularExpression) != nil,
              let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        else { feedback = "金额请填写最多两位小数的人民币元。"; return }
        guard decimal <= 1_000_000 else {
            feedback = "金额须在 0.01 元至 100 万元之间。"; return
        }
        let fen = NSDecimalNumber(decimal: decimal * 100).int64Value
        guard fen > 0 && fen <= 100_000_000 else {
            feedback = "金额须在 0.01 元至 100 万元之间。"; return
        }
        busy = true
        feedback = ""
        let requestStoreID = storeID.isEmpty ? nil : storeID
        let requestCustomerLabel = storeID.isEmpty
            ? customerLabel.trimmingCharacters(in: .whitespaces) : nil
        let paidAtComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: paidAt)
        let requestPaidAt = Calendar.current.date(from: paidAtComponents) ?? paidAt
        let requestVoucherReference = voucherReference.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : voucherReference.trimmingCharacters(in: .whitespaces)
        let requestNote = note.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : note.trimmingCharacters(in: .whitespaces)
        let retry = pendingWriteRetryKey(scope: "operator-charge-create:\(operatorID)", payload: [
            "StoreId": requestStoreID ?? "",
            "CustomerLabel": requestCustomerLabel ?? "",
            "Channel": channel,
            "AmountFen": String(fen),
            "PaidAtUtc": ISO8601DateFormatter().string(from: requestPaidAt),
            "VoucherReference": requestVoucherReference ?? "",
            "Note": requestNote ?? ""
        ])
        let requestToken = token
        let generation = tokenGeneration
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let created = try await api.operatorCreateCharge(token: requestToken,
                    storeID: requestStoreID, customerLabel: requestCustomerLabel,
                    channel: channel, amountFen: fen, paidAt: requestPaidAt,
                    voucherReference: requestVoucherReference,
                    note: requestNote, idempotencyKey: retry.key)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                clearPendingWriteRetryKey(retry)
                if let index = charges.firstIndex(where: { $0.Id == created.Id }) {
                    charges[index] = created
                } else {
                    charges.insert(created, at: 0)
                }
                amount = ""; voucherReference = ""; note = ""
                feedback = "已提交，等待管理员核对。"
                do {
                    let refreshed = try await api.operatorCharges(token: requestToken)
                    guard isCurrentToken(requestToken, generation: generation) else { return }
                    charges = refreshed
                    hasOlderCharges = refreshed.count >= 100
                } catch {
                    guard isCurrentToken(requestToken, generation: generation) else { return }
                    feedback = "收费记录已提交，但列表刷新失败；可点“刷新”重试。"
                }
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                feedback = error.localizedDescription
            }
        }
    }

    private func refresh(token requestToken: String, generation: Int) async {
        do {
            let nextStores = try await api.operatorStores(token: requestToken)
            guard isCurrentToken(requestToken, generation: generation) else { return }
            let nextCharges = try await api.operatorCharges(token: requestToken)
            guard isCurrentToken(requestToken, generation: generation) else { return }
            stores = nextStores
            hasOlderStores = nextStores.count >= 100
            charges = nextCharges
            hasOlderCharges = nextCharges.count >= 100
        } catch {
            guard isCurrentToken(requestToken, generation: generation) else { return }
            feedback = error.localizedDescription
        }
    }

    private func loadOlderStores() {
        guard !busy, hasOlderStores, let cursor = stores.last?.Id else { return }
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let older = try await api.operatorStores(token: requestToken, beforeID: cursor)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                let existing = Set(stores.map(\.Id))
                stores.append(contentsOf: older.filter { !existing.contains($0.Id) })
                hasOlderStores = older.count >= 100
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                feedback = error.localizedDescription
            }
        }
    }

    private func loadOlderCharges() {
        guard !busy, hasOlderCharges, let cursor = charges.last?.Id else { return }
        let requestToken = token
        let generation = tokenGeneration
        busy = true
        Task {
            defer { if isCurrentToken(requestToken, generation: generation) { busy = false } }
            do {
                let older = try await api.operatorCharges(token: requestToken, beforeID: cursor)
                guard isCurrentToken(requestToken, generation: generation) else { return }
                let existing = Set(charges.map(\.Id))
                charges.append(contentsOf: older.filter { !existing.contains($0.Id) })
                hasOlderCharges = older.count >= 100
            } catch {
                guard isCurrentToken(requestToken, generation: generation) else { return }
                feedback = error.localizedDescription
            }
        }
    }

    private func isCurrentToken(_ requestToken: String, generation: Int) -> Bool {
        activeToken == requestToken && token == requestToken && tokenGeneration == generation
    }

    private func channelName(_ code: String) -> String {
        channels.first(where: { $0.0 == code })?.1 ?? code
    }

    private func statusName(_ status: String) -> String {
        switch status {
        case "verified": "已核对"
        case "rejected": "已驳回"
        default: "待核对"
        }
    }
}

final class DineWiseLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
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
        } else if manager.authorizationStatus == .denied
            || manager.authorizationStatus == .restricted {
            error = "未取得定位权限"
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

struct DineWiseCameraPicker: UIViewControllerRepresentable {
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
