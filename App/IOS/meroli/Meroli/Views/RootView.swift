import SwiftUI
import AuthenticationServices
import CryptoKit

private enum MeroliColor {
    static let ink = Color(red: 23 / 255, green: 63 / 255, blue: 58 / 255)
    static let canvas = Color(red: 1, green: 253 / 255, blue: 248 / 255)
    static let muted = Color(red: 73 / 255, green: 102 / 255, blue: 97 / 255)
    static let line = Color(red: 212 / 255, green: 223 / 255, blue: 218 / 255)
    static let gold = Color(red: 239 / 255, green: 181 / 255, blue: 62 / 255)
    static let coral = Color(red: 190 / 255, green: 77 / 255, blue: 64 / 255)
    static let paleGreen = Color(red: 235 / 255, green: 243 / 255, blue: 238 / 255)
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            MeroliColor.canvas.ignoresSafeArea()
            Group {
                switch session.phase {
                case .restoring: LoadingView()
                case .restoreUnavailable: SessionRestoreUnavailableView()
                case .signedOut: SignInView()
                case .signedIn: FamilyTabView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.canvas.ignoresSafeArea())
        .tint(MeroliColor.ink)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }
}

private struct SessionRestoreUnavailableView: View {
    @Environment(SessionStore.self) private var session
    private var zh: Bool { session.usesChinese }

    var body: some View {
        VStack(spacing: 18) {
            Image("MeroliMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(zh ? "暂时无法连接 Meroli" : "Meroli is temporarily unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(MeroliColor.ink)
            Text(session.errorMessage ?? (zh ? "请检查网络后重试。" : "Check your connection and try again."))
                .font(.subheadline)
                .foregroundStyle(MeroliColor.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await session.restore() }
            } label: {
                HStack {
                    if session.isRestoringSession { ProgressView().tint(.white) }
                    Text(zh ? "重试连接" : "Try again")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(session.isRestoringSession)
            Button(zh ? "使用其他账户登录" : "Sign in with another account") {
                Task { await session.logout() }
            }
            .disabled(session.isRestoringSession)
        }
        .padding(26)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.canvas.ignoresSafeArea())
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("MeroliMark")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            ProgressView().tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeroliColor.ink.ignoresSafeArea())
    }
}

private struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var showsPasswordReset = false
    @State private var appleRawNonce: String?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }
    private var zh: Bool { session.usesChinese }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    Image("MeroliMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meroli")
                            .font(.system(size: 25, weight: .bold, design: .serif))
                            .foregroundStyle(MeroliColor.ink)
                        Text("Your School Daily")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                    }
                }
                .padding(.bottom, 43)

                Text(createAccount ? (zh ? "创建家庭账户" : "Create your family account") : (zh ? "欢迎回来" : "Welcome back"))
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(MeroliColor.ink)
                Text(zh ? "从一个共享的家庭账户开始。" : "Start with one shared family account.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                    .padding(.top, 8)
                    .padding(.bottom, 27)

                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(zh ? "邮箱" : "Email")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MeroliColor.ink)
                        TextField("name@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .textFieldStyle(MeroliFieldStyle())
                            .accessibilityIdentifier("meroli.email")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(zh ? "密码" : "Password")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MeroliColor.ink)
                        SecureField(zh ? "输入密码" : "Enter password", text: $password)
                            .textContentType(createAccount ? .newPassword : .password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit(submit)
                            .textFieldStyle(MeroliFieldStyle())
                            .accessibilityIdentifier("meroli.password")
                    }
                }

                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(MeroliColor.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 15)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if session.isAuthenticating { ProgressView().tint(.white) }
                        Text(createAccount ? (zh ? "创建账户" : "Create account") : (zh ? "登录" : "Sign in"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .disabled(session.isAuthenticating)
                .padding(.top, 22)
                .accessibilityIdentifier("meroli.submit")

                SignInWithAppleButton(.signIn, onRequest: { request in
                    let nonce = AppleNonce.generate()
                    appleRawNonce = nonce
                    request.nonce = AppleNonce.sha256(nonce)
                    request.requestedScopes = [.email, .fullName]
                }, onCompletion: { result in
                    guard case .success(let authorization) = result,
                          let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let token = String(data: tokenData, encoding: .utf8),
                          let nonce = appleRawNonce else {
                        if case .failure(let error) = result { session.errorMessage = error.localizedDescription }
                        return
                    }
                    Task { await session.signInWithApple(identityToken: token, rawNonce: nonce) }
                })
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.top, 14)

                if !createAccount {
                    Button(zh ? "忘记密码？" : "Forgot password?") { showsPasswordReset = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .accessibilityIdentifier("meroli.passwordReset")
                }

                Button {
                    createAccount.toggle()
                    session.errorMessage = nil
                } label: {
                    HStack(spacing: 5) {
                        Text(createAccount ? (zh ? "已有账户？" : "Already have an account?") : (zh ? "还没有账户？" : "New to Meroli?"))
                            .foregroundStyle(MeroliColor.muted)
                        Text(createAccount ? (zh ? "登录" : "Sign in") : (zh ? "创建账户" : "Create one"))
                            .fontWeight(.semibold)
                            .foregroundStyle(MeroliColor.ink)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 26)
            .padding(.top, 40)
            .padding(.bottom, 34)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MeroliColor.canvas)
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetRequestView(email: $email)
                .presentationDetents([.medium])
        }
    }

    private func submit() {
        focusedField = nil
        Task { await session.signIn(email: email, password: password, createAccount: createAccount) }
    }
}

private struct PasswordResetRequestView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String
    @State private var isSending = false
    @State private var sent = false
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(zh ? "输入账户邮箱，我们会发送密码重置说明。" : "Enter your account email and we’ll send password reset instructions.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                TextField("name@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(MeroliFieldStyle())
                    .disabled(sent)
                if sent {
                    Label(zh ? "如果账户存在，重置说明将发送到邮箱。" : "If an account exists, reset instructions will be sent by email.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(MeroliColor.ink)
                } else if let error = session.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                }
                Button {
                    isSending = true
                    Task {
                        sent = await session.requestPasswordReset(email: email)
                        isSending = false
                    }
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text(zh ? "发送说明" : "Send instructions")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(isSending || sent)
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "重置密码" : "Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "完成" : "Done") { dismiss() } } }
        }
    }
}

private struct FamilyTabView: View {
    @Environment(SessionStore.self) private var session
    @State private var selected = 0
    private var zh: Bool { session.usesChinese }

    var body: some View {
        TabView(selection: $selected) {
            HomeScreen()
                .tag(0)
                .tabItem { Label(zh ? "今天" : "Today", systemImage: "sun.max") }
            FamilyScreen()
                .tag(1)
                .tabItem { Label(zh ? "家庭" : "Family", systemImage: "person.2") }
            CalendarScreen()
                .tag(2)
                .tabItem { Label(zh ? "日历" : "Calendar", systemImage: "calendar") }
            SettingsScreen()
                .tag(3)
                .tabItem { Label(zh ? "设置" : "Settings", systemImage: "gearshape") }
        }
        .toolbarBackground(MeroliColor.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct HomeScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var date = Date()
    private var zh: Bool { session.usesChinese }
    private static var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(zh ? "今天的上学安排" : "Today at school")
                        .font(.system(size: 29, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                    HStack {
                        Button { date = Self.schoolCalendar.date(byAdding: .day, value: -1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(schoolDateLabel(date))
                            .font(.headline)
                        Spacer()
                        Button { date = Self.schoolCalendar.date(byAdding: .day, value: 1, to: date) ?? date; refresh() } label: { Image(systemName: "chevron.right") }
                    }
                    if let error = session.homeErrorMessage, !session.dailySchedules.isEmpty {
                        homeErrorCard(error)
                    }
                    if session.isLoadingFamily || session.isLoadingHome {
                        ProgressView(zh ? "正在读取学校安排…" : "Loading school schedules…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if let error = session.homeErrorMessage, session.dailySchedules.isEmpty {
                        homeErrorCard(error)
                    } else if session.dailySchedules.isEmpty {
                        Text(zh ? "还没有可显示的孩子学校安排。请在家庭页添加孩子并设置学校。" : "No school schedules yet. Add a child and school in Family.")
                            .foregroundStyle(MeroliColor.muted).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        ForEach(session.dailySchedules) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.childName).font(.headline).foregroundStyle(MeroliColor.ink)
                                        Text(item.schoolName ?? (zh ? "未设置学校" : "No school selected"))
                                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                    }
                                    Spacer()
                                    Text(statusLabel(item.status)).font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(MeroliColor.paleGreen, in: Capsule())
                                }
                                if item.status == "OK" {
                                    HStack(spacing: 20) {
                                        scheduleTime(title: zh ? "到校" : "Arrival", value: item.arrivalTime)
                                        scheduleTime(title: zh ? "放学" : "Dismissal", value: item.dismissalTime)
                                    }
                                    if let code = item.scheduleCode { Text(code).font(.caption).foregroundStyle(MeroliColor.muted) }
                                    if let periods = item.periods, !periods.isEmpty {
                                        VStack(spacing: 0) {
                                            ForEach(periods) { period in
                                                HStack(spacing: 10) {
                                                    Text(zh && !period.labelZh.isEmpty ? period.labelZh : period.labelEn)
                                                        .font(.caption.weight(.medium)).foregroundStyle(MeroliColor.ink)
                                                    Spacer(minLength: 4)
                                                    Text("\(period.startTime)–\(period.endTime)")
                                                        .font(.caption.monospacedDigit()).foregroundStyle(MeroliColor.muted)
                                                    if period.isOptional {
                                                        Text(zh ? "可选" : "Optional").font(.caption2).foregroundStyle(MeroliColor.muted)
                                                    }
                                                }
                                                .padding(.vertical, 7)
                                                if period.id != periods.last?.id { Divider().overlay(MeroliColor.line) }
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                if !item.eventTitles.isEmpty {
                                    ForEach(item.eventTitles, id: \.self) { title in Label(title, systemImage: "calendar.badge.exclamationmark").font(.subheadline) }
                                }
                            }
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { refresh() } label: { Image(systemName: "arrow.clockwise") } } }
            .refreshable {
                await session.loadFamily()
                await session.loadDailySchedules(for: date)
            }
            .task { if session.dailySchedules.isEmpty { refresh() } }
            .onChange(of: session.children.count) { refresh() }
        }
    }

    private func refresh() { Task { await session.loadDailySchedules(for: date) } }

    private func homeErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(zh ? "暂时无法读取家庭安排" : "Schedules are unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(MeroliColor.coral)
            Text(error).font(.subheadline).foregroundStyle(MeroliColor.muted)
            Button(zh ? "重试" : "Try again") {
                Task {
                    await session.loadFamily()
                    await session.loadDailySchedules(for: date)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func schoolDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Self.schoolCalendar
        formatter.timeZone = Self.schoolCalendar.timeZone
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "OK": return zh ? "正常上课" : "School day"
        case "NO_SCHOOL": return zh ? "不上课" : "No school"
        case "NO_ENROLLMENT": return zh ? "未设置学校" : "No enrollment"
        case "NON_INSTRUCTIONAL_DAY": return zh ? "非上课日" : "Non-instructional day"
        case "EVENT_SCHEDULE_CONFLICT": return zh ? "活动课表冲突" : "Event schedule conflict"
        case "SCHEDULE_TEMPLATE_UNRESOLVED", "SCHEDULE_VARIANT_UNRESOLVED": return zh ? "课表需要确认" : "Schedule needs review"
        case "SCHEDULE_DATA_UNAVAILABLE", "SCHEDULE_UNAVAILABLE", "SCHEDULE_DATA_INCOMPLETE": return zh ? "暂无可靠课表" : "Schedule unavailable"
        default: return zh ? "暂无课表" : "Schedule unavailable"
        }
    }

    private func scheduleTime(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(MeroliColor.muted)
            Text(value ?? "—").font(.title3.weight(.semibold)).foregroundStyle(MeroliColor.ink)
        }
    }
}

private struct CalendarScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var month = Date()
    @State private var selectedChildId = ""
    @State private var selectedEvent: ParentEventDTO?
    private var zh: Bool { session.usesChinese }
    private static var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }
    private var monthTitle: String {
        month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: zh ? "zh_CN" : "en_US")))
    }
    private var range: (Date, Date) {
        let components = Self.schoolCalendar.dateComponents([.year, .month], from: month)
        let start = Self.schoolCalendar.date(from: components) ?? month
        var next = DateComponents()
        next.month = 1
        next.day = -1
        let end = Self.schoolCalendar.date(byAdding: next, to: start) ?? start
        return (start, end)
    }
    private var groupedEvents: [(String, [ParentEventDTO])] {
        let groups = Dictionary(grouping: session.calendarEvents, by: \.startDate)
        return groups.keys.sorted().map { ($0, groups[$0, default: []]) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                        .accessibilityLabel(zh ? "上个月" : "Previous month")
                    Spacer()
                    Text(monthTitle).font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                        .accessibilityLabel(zh ? "下个月" : "Next month")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                if session.children.count > 1 {
                    Picker(zh ? "孩子" : "Child", selection: $selectedChildId) {
                        Text(zh ? "全部孩子" : "All children").tag("")
                        ForEach(session.children) { child in Text(child.nickname).tag(child.id) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 19)
                    .padding(.top, 8)
                    .onChange(of: selectedChildId) { _, _ in Task { await load() } }
                }

                if session.isLoadingCalendar && session.calendarEvents.isEmpty {
                    ProgressView(zh ? "正在读取日历…" : "Loading calendar…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = session.errorMessage, session.calendarEvents.isEmpty {
                    VStack(spacing: 14) {
                        Label(zh ? "暂时无法读取日历" : "Calendar unavailable", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(MeroliColor.ink)
                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.muted).multilineTextAlignment(.center)
                        Button(zh ? "重试" : "Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if session.calendarEvents.isEmpty {
                    ContentUnavailableView(
                        zh ? "这个月还没有活动" : "No events this month",
                        systemImage: "calendar",
                        description: Text(zh ? "学校公告和家庭日程会显示在这里。" : "School announcements and family events will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedEvents, id: \.0) { date, events in
                            Section {
                                ForEach(events) { event in
                                    Button { selectedEvent = event } label: {
                                        EventRow(event: event, zh: zh)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.white)
                                }
                            } header: {
                                Text(formattedDate(date))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MeroliColor.muted)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(MeroliColor.canvas)
                    .refreshable { await load() }
                }
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "日历" : "Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "本月" : "Today") { month = monthStart(.now); Task { await load() } }
                }
            }
            .task { await load() }
            .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event, zh: zh) }
        }
    }

    private func shiftMonth(_ amount: Int) {
        month = Self.schoolCalendar.date(byAdding: .month, value: amount, to: month) ?? month
        Task { await load() }
    }

    private func load() async {
        let (start, end) = range
        await session.loadCalendar(from: start, to: end, childId: selectedChildId.isEmpty ? nil : selectedChildId)
    }

    private func monthStart(_ date: Date) -> Date {
        let parts = Self.schoolCalendar.dateComponents([.year, .month], from: date)
        return Self.schoolCalendar.date(from: parts) ?? date
    }

    private func formattedDate(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Self.schoolCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

private struct EventRow: View {
    let event: ParentEventDTO
    let zh: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(event.parentRelevance == "ACTION_REQUIRED" ? MeroliColor.coral : MeroliColor.gold)
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(event.title).font(.headline).foregroundStyle(MeroliColor.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                }
                HStack(spacing: 6) {
                    if !event.allDay, let start = event.startTime { Text(String(start.prefix(5))) }
                    if !event.children.isEmpty {
                        Text(event.children.map(\.name).joined(separator: ", "))
                    } else if !event.schools.isEmpty {
                        Text(event.schools.map(\.name).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(MeroliColor.muted)
                if !event.action.isEmpty {
                    Text(event.action).font(.subheadline).foregroundStyle(MeroliColor.coral).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct EventDetailSheet: View {
    let event: ParentEventDTO
    let zh: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(event.title).font(.system(size: 28, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                    Label(event.allDay ? (zh ? "全天" : "All day") : [event.startTime.map { String($0.prefix(5)) }, event.endTime.map { String($0.prefix(5)) }].compactMap { $0 }.joined(separator: "–"), systemImage: "clock")
                        .font(.subheadline).foregroundStyle(MeroliColor.muted)
                    if !event.explanation.isEmpty { Text(event.explanation).font(.body).foregroundStyle(MeroliColor.ink) }
                    if !event.action.isEmpty {
                        Label(event.action, systemImage: "checkmark.circle")
                            .font(.body.weight(.medium)).foregroundStyle(MeroliColor.coral)
                    }
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(MeroliColor.muted)
                    }
                    if !event.children.isEmpty {
                        Label(event.children.map(\.name).joined(separator: ", "), systemImage: "person.2")
                            .font(.subheadline).foregroundStyle(MeroliColor.muted)
                    }
                    if let sourceURL = URL(string: event.sourceUrl) {
                        Link(destination: sourceURL) {
                            Label(zh ? "查看官方来源 · \(event.sourceName)" : "Official source · \(event.sourceName)", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "活动详情" : "Event details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CloseSheetButton(zh: zh) } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CloseSheetButton: View {
    @Environment(\.dismiss) private var dismiss
    let zh: Bool
    var body: some View { Button(zh ? "完成" : "Done") { dismiss() } }
}

private struct FamilyScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var showsAddChild = false
    @State private var editingChild: ChildDTO?
    @State private var managingSchoolChild: ChildDTO?
    @State private var managingScheduleChild: ChildDTO?
    @State private var viewingSchoolInfo: EnrollmentDTO?
    @State private var choosingNextSchool: SchoolYearTransitionDTO?
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image("MeroliMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Meroli")
                            .font(.system(size: 21, weight: .bold, design: .serif))
                            .foregroundStyle(MeroliColor.ink)
                        Spacer()
                        Button { Task { await session.loadFamily() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 40, height: 40)
                                .background(.white, in: Circle())
                        }
                        .accessibilityLabel(zh ? "刷新家庭" : "Refresh family")
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(zh ? "我的家庭" : "My family")
                            .font(.system(size: 29, weight: .bold, design: .serif))
                            .foregroundStyle(MeroliColor.ink)
                        Text(session.family?.name?.isEmpty == false ? session.family!.name! : session.email)
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.muted)
                    }

                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MeroliColor.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !session.schoolYearTransitions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(zh ? "下一学年安排" : "Next school year", systemImage: "arrow.forward.calendar")
                                .font(.headline)
                                .foregroundStyle(MeroliColor.ink)
                            ForEach(session.schoolYearTransitions) { transition in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(transition.childName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                            Text(transition.graduating
                                                 ? (zh ? "即将完成当前学校阶段 · \(transition.schoolName)" : "Finishing this school stage · \(transition.schoolName)")
                                                 : (zh ? "\(transition.schoolName) · \(transition.schoolYearLabel) 升至 \(transition.suggestedGradeCode.map(localizedGrade) ?? localizedGrade(transition.gradeCode))" : "\(transition.schoolName) · \(transition.schoolYearLabel) to grade \(transition.suggestedGradeCode ?? transition.gradeCode)"))
                                                .font(.caption)
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        Spacer(minLength: 0)
                                        if let year = transition.targetSchoolYearLabel {
                                            Text(year).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                        }
                                    }
                                    if transition.graduating {
                                        HStack {
                                            if transition.targetSchoolYearId != nil {
                                                Button(zh ? "选择下一所学校" : "Choose next school") {
                                                    choosingNextSchool = transition
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(MeroliColor.ink)
                                            }
                                            Button(zh ? "暂不确定" : "Not sure yet") {
                                                Task { _ = await session.applySchoolYearTransition(childId: transition.childId, action: "not-sure") }
                                            }
                                            .buttonStyle(.bordered)
                                            if transition.finishedK12Available {
                                                Button(zh ? "已完成 K–12" : "Finished K–12") {
                                                    Task { _ = await session.applySchoolYearTransition(childId: transition.childId, action: "finished-k12") }
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                        .disabled(session.isSavingSchoolYearTransition)
                                    } else if let targetYearId = transition.targetSchoolYearId, let grade = transition.suggestedGrade {
                                        Button {
                                            Task {
                                                _ = await session.applySchoolYearTransition(childId: transition.childId,
                                                    action: "confirm-grade", targetYearId: targetYearId, grade: grade)
                                            }
                                        } label: {
                                            Label(zh ? "确认升至\(transition.suggestedGradeCode.map(localizedGrade) ?? "下一")" : "Confirm grade \(transition.suggestedGradeCode ?? "")",
                                                systemImage: "checkmark.circle")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(MeroliColor.ink)
                                        .disabled(session.isSavingSchoolYearTransition)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            Text(zh ? "升年级后需要重新确认作息和课后项目。" : "Schedule and after-school programs need reconfirmation each school year.")
                                .font(.caption)
                                .foregroundStyle(MeroliColor.muted)
                        }
                        .padding(15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(MeroliColor.line, lineWidth: 1))
                    }

                    HStack {
                        Text(zh ? "家庭成员" : "Children")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundStyle(MeroliColor.ink)
                        Spacer()
                        Text("\(session.children.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MeroliColor.muted)
                    }

                    if session.isLoadingFamily && session.children.isEmpty {
                        ProgressView(zh ? "正在读取家庭资料…" : "Loading family…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if session.children.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 28))
                                .foregroundStyle(MeroliColor.ink)
                            Text(zh ? "添加家庭成员" : "Add a child to your family")
                                .font(.headline)
                                .foregroundStyle(MeroliColor.ink)
                            Text(zh ? "创建孩子资料后，可以继续关联学校信息。" : "Create a child profile to start building your family's school information.")
                                .font(.subheadline)
                                .foregroundStyle(MeroliColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { showsAddChild = true } label: {
                                Label(zh ? "添加孩子" : "Add child", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 11)
                                    .foregroundStyle(.white)
                                    .background(MeroliColor.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(MeroliColor.line, lineWidth: 1))
                    } else {
                        VStack(spacing: 11) {
                            ForEach(session.children) { child in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button { editingChild = child } label: {
                                        HStack(spacing: 13) {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                                .frame(width: 46, height: 46)
                                                .background(MeroliColor.paleGreen, in: Circle())
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(child.nickname)
                                                    .font(.headline)
                                                    .foregroundStyle(MeroliColor.ink)
                                                Text(zh ? "家庭成员 · 编辑称呼" : "Family member · Edit name")
                                                    .font(.caption)
                                                    .foregroundStyle(MeroliColor.muted)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("meroli.child.\(child.id)")

                                    Divider().overlay(MeroliColor.line).padding(.vertical, 12)

                                    Button { managingSchoolChild = child } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: "building.2")
                                                .foregroundStyle(MeroliColor.ink)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(currentEnrollment(for: child)?.schoolName ?? (zh ? "尚未关联学校" : "No school linked yet"))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(MeroliColor.ink)
                                                Text(currentEnrollment(for: child).map { "\($0.schoolYearName) · \(localizedGrade($0.gradeCode))" } ?? (zh ? "添加孩子的学校与年级" : "Add this child’s school and grade"))
                                                    .font(.caption)
                                                    .foregroundStyle(MeroliColor.muted)
                                            }
                                            Spacer()
                                            Text(currentEnrollment(for: child) == nil ? (zh ? "添加" : "Add") : (zh ? "管理" : "Manage"))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.ink)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MeroliColor.muted)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("meroli.child.school.\(child.id)")

                                    if let enrollment = currentEnrollment(for: child) {
                                        Button { viewingSchoolInfo = enrollment } label: {
                                            Label(zh ? "学校考勤与表现资料" : "Attendance and school information", systemImage: "building.2.crop.circle")
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 11)
                                    }

                                    if currentEnrollment(for: child) != nil {
                                        Divider().overlay(MeroliColor.line).padding(.vertical, 12)
                                        Button { managingScheduleChild = child } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: "clock.badge.checkmark").foregroundStyle(MeroliColor.ink)
                                                Text(zh ? "个性化作息与课后项目" : "Schedule and after-school programs")
                                                    .font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(MeroliColor.line.opacity(0.75), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 19)
                .padding(.top, 13)
                .padding(.bottom, 28)
            }
            .background(MeroliColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await session.loadFamily() }
            .task { if session.family == nil { await session.loadFamily() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAddChild = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(zh ? "添加孩子" : "Add child")
                }
            }
            .sheet(isPresented: $showsAddChild) { AddChildSheet() }
            .sheet(item: $editingChild) { child in RenameChildSheet(child: child) }
            .sheet(item: $managingSchoolChild) { child in
                EnrollmentEditorSheet(child: child, current: currentEnrollment(for: child))
            }
            .sheet(item: $managingScheduleChild) { child in
                if let enrollment = currentEnrollment(for: child) {
                    ScheduleProfileSheet(child: child, schoolId: enrollment.schoolId)
                }
            }
            .sheet(item: $viewingSchoolInfo) { enrollment in
                ParentSchoolOverviewSheet(schoolId: enrollment.schoolId, schoolName: enrollment.schoolName)
            }
            .sheet(item: $choosingNextSchool) { transition in
                NextSchoolTransitionSheet(transition: transition)
            }
        }
    }

    private func currentEnrollment(for child: ChildDTO) -> EnrollmentDTO? {
        session.enrollments.first { $0.childId == child.id && $0.isCurrent }
    }

    private func localizedGrade(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
    }
}

private struct NextSchoolTransitionSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let transition: SchoolYearTransitionDTO
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var gradeCode = ""
    @State private var selectedProgramIds: Set<String> = []
    @State private var didLoad = false
    private var zh: Bool { session.usesChinese }
    private var school: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }

    var body: some View {
        NavigationStack {
            Form {
                Section(zh ? "下一学年" : "Next school year") {
                    LabeledContent(zh ? "孩子" : "Child", value: transition.childName)
                    LabeledContent(zh ? "学年" : "School year", value: transition.targetSchoolYearLabel ?? "—")
                }
                Section(zh ? "学校" : "School") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        ForEach(session.districts) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        selectedProgramIds = []
                        guard !value.isEmpty else { return }
                        Task { await session.loadSchools(districtId: value) }
                    }
                    if session.isLoadingSchools {
                        ProgressView(zh ? "正在读取学校…" : "Loading schools…")
                    } else {
                        Picker(zh ? "学校" : "School", selection: $schoolId) {
                            Text(zh ? "请选择学校" : "Choose a school").tag("")
                            ForEach(session.schools) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: schoolId) { _, value in
                            gradeCode = ""
                            selectedProgramIds = []
                            guard !value.isEmpty else { return }
                            Task { await session.loadTransitionPrograms(schoolId: value) }
                        }
                    }
                    if let school {
                        Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                            Text(zh ? "请选择年级" : "Choose a grade").tag("")
                            ForEach(school.availableGrades, id: \.self) { Text(localizedGrade($0)).tag($0) }
                        }
                    }
                }
                if !schoolId.isEmpty {
                    Section(zh ? "课后项目（可选）" : "After-school programs (optional)") {
                        if session.transitionPrograms.isEmpty {
                            Text(zh ? "该校目前没有可选项目；稍后可在家庭页补充。" : "No programs are currently listed. You can update this later.")
                                .font(.footnote).foregroundStyle(MeroliColor.muted)
                        } else {
                            ForEach(session.transitionPrograms) { program in
                                Button {
                                    if selectedProgramIds.contains(program.id) {
                                        selectedProgramIds.remove(program.id)
                                    } else {
                                        selectedProgramIds.insert(program.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(zh ? program.displayNameZh : program.displayNameEn)
                                            .foregroundStyle(MeroliColor.ink)
                                        Spacer()
                                        if selectedProgramIds.contains(program.id) {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.footnote).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button(zh ? "确认下一学年学校" : "Confirm next school") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(session.isSavingSchoolYearTransition || school == nil || gradeCode.isEmpty || transition.targetSchoolYearId == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "选择下一所学校" : "Choose next school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "关闭" : "Close") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        await session.loadSchoolCatalog()
        districtId = session.districts.first(where: { $0.id == transition.districtId })?.id ?? session.districts.first?.id ?? ""
        if !districtId.isEmpty { await session.loadSchools(districtId: districtId) }
    }

    private func save() {
        guard let grade = numericGrade(gradeCode), let yearId = transition.targetSchoolYearId else { return }
        Task {
            let saved = await session.applySchoolYearTransition(childId: transition.childId,
                action: "next-school", targetYearId: yearId, extraPayload: [
                    "school_id": schoolId,
                    "grade": grade,
                    "program_ids": Array(selectedProgramIds)
                ])
            if saved { dismiss() }
        }
    }

    private func numericGrade(_ code: String) -> Int? {
        switch code {
        case "PK": return -2
        case "TK": return -1
        case "K": return 0
        default: return Int(code)
        }
    }

    private func localizedGrade(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
    }
}

private struct ScheduleProfileSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    let schoolId: String
    @State private var selectionStatus = "NOT_SURE"
    @State private var variantCode = "DEFAULT"
    @State private var programIds: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(zh ? "设置 \(child.nickname) 的学校作息" : "Set \(child.nickname)’s school schedule")
                        .font(.system(size: 25, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                    if isLoading {
                        ProgressView(zh ? "正在读取学校提供的选项…" : "Loading school options…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if let profile = session.scheduleProfile {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "课表变体" : "Schedule variant").font(.headline)
                            Picker(zh ? "课表变体" : "Schedule variant", selection: $variantCode) {
                                ForEach(profile.availableVariantCodes, id: \.self) { code in Text(code).tag(code) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zh ? "课后项目" : "After-school programs").font(.headline)
                            Picker(zh ? "项目选择" : "Program selection", selection: $selectionStatus) {
                                Text(zh ? "需要选择" : "Select programs").tag("SELECTED")
                                Text(zh ? "没有项目" : "No programs").tag("NONE")
                                Text(zh ? "暂不确定" : "Not sure yet").tag("NOT_SURE")
                            }
                            .pickerStyle(.segmented)
                            if profile.programs.isEmpty {
                                Text(zh ? "学校还没有发布可选的课后项目。" : "The school has not published any selectable programs.")
                                    .font(.subheadline).foregroundStyle(MeroliColor.muted)
                            } else {
                                ForEach(profile.programs) { program in
                                    Toggle(isOn: Binding(
                                        get: { programIds.contains(program.id) },
                                        set: { enabled in
                                            if enabled { programIds.insert(program.id) }
                                            else { programIds.remove(program.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(zh && !program.displayNameZh.isEmpty ? program.displayNameZh : program.displayNameEn)
                                                .font(.subheadline.weight(.medium))
                                            if program.affectsArrivalTime, let period = program.periodCode {
                                                Text(zh ? "影響到校時間 · \(period)" : "Affects arrival · \(period)")
                                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                            }
                                        }
                                    }
                                    .disabled(selectionStatus != "SELECTED")
                                }
                            }
                        }
                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        Text(zh ? "这些选择用于计算每日到校时间；不确定时可以保留默认选项。" : "These choices personalize daily arrival times. You can leave them as unsure.")
                            .font(.footnote).foregroundStyle(MeroliColor.muted)
                    } else if let error = session.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                    }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "作息偏好" : "Schedule preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(zh ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(zh ? "保存" : "Save") { save() }
                        .disabled(isLoading || isSaving || (selectionStatus == "SELECTED" && programIds.isEmpty))
                }
            }
            .task {
                await session.loadScheduleProfile(child: child, schoolId: schoolId)
                if let profile = session.scheduleProfile, profile.childId == child.id, profile.schoolId == schoolId {
                    selectionStatus = profile.selectionStatus
                    variantCode = profile.scheduleVariantCode
                    programIds = Set(profile.programIds)
                }
                isLoading = false
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await session.saveScheduleProfile(child: child, selectionStatus: selectionStatus,
                variantCode: variantCode, programIds: Array(programIds))
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ParentSchoolOverviewSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let schoolId: String
    let schoolName: String
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(session.schoolOverview?.schoolName ?? schoolName)
                        .font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                    if session.isLoadingSchoolOverview {
                        ProgressView(zh ? "正在读取学校资料…" : "Loading school information…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else if let overview = session.schoolOverview {
                        if let attendance = overview.attendance {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(zh ? "考勤与请假" : "Attendance and absence reporting").font(.headline).foregroundStyle(MeroliColor.ink)
                                Text(attendance.attendanceMethod).font(.subheadline.weight(.semibold))
                                if !attendance.absenceInstruction.isEmpty {
                                    infoParagraph(title: zh ? "缺课" : "Absence", text: attendance.absenceInstruction)
                                }
                                if !attendance.lateArrivalInstruction.isEmpty {
                                    infoParagraph(title: zh ? "迟到" : "Late arrival", text: attendance.lateArrivalInstruction)
                                }
                                if !attendance.earlyPickupInstruction.isEmpty {
                                    infoParagraph(title: zh ? "提前接送" : "Early pickup", text: attendance.earlyPickupInstruction)
                                }
                                if let phone = attendance.attendancePhone, !phone.isEmpty {
                                    Label(phone, systemImage: "phone").font(.subheadline)
                                }
                                if let email = attendance.attendanceEmail, !email.isEmpty {
                                    Label(email, systemImage: "envelope").font(.subheadline)
                                }
                                if let url = URL(string: attendance.attendanceUrl ?? "") {
                                    Link(destination: url) { Label(zh ? "打开学校请假页面" : "Open school attendance page", systemImage: "arrow.up.right.square") }
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text((zh ? "最后核实：" : "Last verified: ") + String(attendance.lastVerifiedAt.prefix(10)))
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if let performance = overview.performance {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(zh ? "学校表现" : "School performance").font(.headline).foregroundStyle(MeroliColor.ink)
                                    Spacer()
                                    Text(performance.academicYear).font(.caption).foregroundStyle(MeroliColor.muted)
                                }
                                Text(performance.availability == "LEGACY"
                                    ? (zh ? "旧版学校概览" : "Legacy school overview")
                                    : "\(performance.sourceName) · \(performance.reportingCycle)")
                                    .font(.caption).foregroundStyle(MeroliColor.muted)
                                ForEach(performance.metrics) { metric in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(metric.metricName).font(.subheadline.weight(.medium)).foregroundStyle(MeroliColor.ink)
                                            Text(metric.officialStatus.replacingOccurrences(of: "_", with: " "))
                                                .font(.caption).foregroundStyle(MeroliColor.muted)
                                        }
                                        Spacer(minLength: 12)
                                        Text(metric.officialValue ?? metric.officialPerformanceLevel ?? "—")
                                            .font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                                    }
                                    Divider().overlay(MeroliColor.line)
                                }
                                Text(performance.disclaimer).font(.caption).foregroundStyle(MeroliColor.muted)
                                if let url = URL(string: performance.sourceUrl) {
                                    Link(destination: url) { Label(zh ? "查看官方来源" : "View official source", systemImage: "arrow.up.right.square") }
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if let history = session.schoolPerformanceHistory, history.cycles.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(zh ? "历年官方表现" : "Official performance history")
                                    .font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(MeroliColor.ink)
                                ForEach(history.cycles.dropFirst(), id: \.reportingCycle) { cycle in
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 9) {
                                            ForEach(cycle.metrics) { metric in
                                                HStack(alignment: .top) {
                                                    Text(metric.metricName).font(.caption).foregroundStyle(MeroliColor.ink)
                                                    Spacer(minLength: 12)
                                                    Text(metric.officialValue ?? metric.officialPerformanceLevel ?? "—")
                                                        .font(.caption.weight(.semibold)).multilineTextAlignment(.trailing)
                                                }
                                            }
                                            Text(cycle.disclaimer).font(.caption2).foregroundStyle(MeroliColor.muted)
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        HStack {
                                            Text(cycle.academicYear).font(.subheadline.weight(.semibold)).foregroundStyle(MeroliColor.ink)
                                            Spacer()
                                            Text(cycle.reportingCycle).font(.caption).foregroundStyle(MeroliColor.muted)
                                        }
                                    }
                                    .tint(MeroliColor.ink)
                                    Divider().overlay(MeroliColor.line)
                                }
                            }
                            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                        if overview.attendance == nil && overview.performance == nil {
                            Text(zh ? "学校尚未发布考勤或表现资料。" : "The school has not published attendance or performance information yet.")
                                .font(.subheadline).foregroundStyle(MeroliColor.muted)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    } else if let error = session.errorMessage {
                        Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                    }
                }
                .padding(20)
            }
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "学校资料" : "School information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "完成" : "Done") { dismiss() } } }
            .task {
                await session.loadSchoolOverview(schoolId: schoolId)
                await session.loadSchoolPerformanceHistory(schoolId: schoolId)
            }
        }
    }

    private func infoParagraph(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(MeroliColor.muted)
            Text(text).font(.subheadline).foregroundStyle(MeroliColor.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EnrollmentEditorSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    let current: EnrollmentDTO?
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var schoolYearId = ""
    @State private var gradeCode = ""
    @State private var hasLoaded = false
    @State private var confirmingEnrollmentAction = false
    @State private var confirmingSchoolChange = false
    @State private var enrollmentAction = "remove"
    private var zh: Bool { session.usesChinese }
    private var selectedSchool: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }
    private var selectedYear: SchoolYearDTO? { session.schoolYears.first { $0.id == schoolYearId } }

    var body: some View {
        NavigationStack {
            Form {
                Section(zh ? "学校" : "School") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        Text(zh ? "选择学区" : "Choose a district").tag("")
                        ForEach(session.districts) { district in
                            Text(district.name).tag(district.id)
                        }
                    }
                    .disabled(session.isLoadingCatalog)
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        guard !value.isEmpty else { return }
                        Task { await session.loadSchools(districtId: value) }
                    }

                    if session.schools.isEmpty && !districtId.isEmpty && session.isLoadingSchools {
                        ProgressView(zh ? "正在读取学校…" : "Loading schools…")
                    } else {
                        Picker(zh ? "学校" : "School", selection: $schoolId) {
                            Text(zh ? "选择学校" : "Choose a school").tag("")
                            ForEach(session.schools) { school in
                                Text(school.name).tag(school.id)
                            }
                        }
                        .disabled(districtId.isEmpty || session.isLoadingSchools)
                        .onChange(of: schoolId) { _, value in
                            let grades = session.schools.first(where: { $0.id == value })?.availableGrades ?? []
                            if !grades.contains(gradeCode) { gradeCode = grades.first ?? "" }
                        }
                    }

                    if let school = selectedSchool {
                        Text([school.address, school.city, school.state, school.postalCode]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(MeroliColor.muted)
                    }
                    if current != nil && schoolId != current?.schoolId && !schoolId.isEmpty {
                        Text(zh ? "保存后会结束原学校记录并保留历史，新学校记录会立即生效。" : "Saving will close the previous school record, keep its history, and activate the new school.")
                            .font(.caption).foregroundStyle(MeroliColor.muted)
                    }
                }

                Section(zh ? "入学资料" : "Enrollment") {
                    Picker(zh ? "学年" : "School year", selection: $schoolYearId) {
                        Text(zh ? "选择学年" : "Choose a school year").tag("")
                        ForEach(session.schoolYears) { year in Text(year.name).tag(year.id) }
                    }
                    .disabled(current != nil || session.isLoadingCatalog)

                    Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                        Text(zh ? "选择年级" : "Choose a grade").tag("")
                        ForEach(selectedSchool?.availableGrades ?? [], id: \.self) { grade in
                            Text(localizedGrade(grade)).tag(grade)
                        }
                    }
                    .disabled(selectedSchool == nil)
                }

                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }

                Section {
                    Button {
                        if current != nil && schoolId != current?.schoolId {
                            confirmingSchoolChange = true
                        } else {
                            save()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if session.isSavingChild { ProgressView().padding(.trailing, 6) }
                            Text(current == nil ? (zh ? "保存学校资料" : "Save school details") : (zh ? "保存变更" : "Save changes"))
                            Spacer()
                        }
                    }
                    .disabled(session.isSavingChild || session.hasPendingSchoolChange(childId: child.id) || selectedSchool == nil || selectedYear == nil || gradeCode.isEmpty)
                }
                if current != nil {
                    Section(zh ? "记录管理" : "Enrollment record") {
                        Button(zh ? "结束此学年记录" : "Mark school year completed") {
                            enrollmentAction = "complete"
                            confirmingEnrollmentAction = true
                        }
                        if session.hasPendingSchoolRemoval(childId: child.id) {
                            Button(zh ? "检查移除状态" : "Check removal status") {
                                Task {
                                    if await session.checkPendingSchoolRemoval(childId: child.id) {
                                        dismiss()
                                    }
                                }
                            }
                            Text(zh ? "上次移除结果尚未确认。请只检查状态，不要重复提交。" : "The previous removal is unconfirmed. Check its status; do not submit it again.")
                                .font(.caption).foregroundStyle(MeroliColor.coral)
                        } else {
                            Button(zh ? "移除此校关联" : "Remove this school") {
                                enrollmentAction = "remove"
                                confirmingEnrollmentAction = true
                            }
                            .foregroundStyle(MeroliColor.coral)
                        }
                    }
                    .disabled(session.isSavingChild)
                    if session.hasPendingSchoolChange(childId: child.id) {
                        Section(zh ? "换校状态待确认" : "School change needs confirmation") {
                            Text(zh ? "为避免重复提交，当前只允许读取服务器状态。" : "Only a read-only status check is available to prevent duplicate changes.")
                                .font(.caption).foregroundStyle(MeroliColor.coral)
                            Button(zh ? "检查换校状态" : "Check school change status") {
                                Task {
                                    if await session.checkPendingSchoolChange(childId: child.id) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "\(child.nickname) 的学校" : "\(child.nickname)’s school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "关闭" : "Close") { dismiss() } } }
            .confirmationDialog(zh ? "确认更新入学记录？" : "Update this enrollment?", isPresented: $confirmingEnrollmentAction, titleVisibility: .visible) {
                if enrollmentAction == "remove" && session.hasPendingSchoolRemoval(childId: child.id) {
                    Button(zh ? "检查移除状态" : "Check removal status") {
                        Task {
                            if await session.checkPendingSchoolRemoval(childId: child.id) {
                                dismiss()
                            }
                        }
                    }
                } else {
                    Button(enrollmentAction == "remove" ? (zh ? "移除关联" : "Remove school") : (zh ? "结束记录" : "Complete record"), role: .destructive) {
                        guard let current else { return }
                        Task {
                            if await session.closeEnrollment(enrollmentId: current.id, action: enrollmentAction) {
                                dismiss()
                            }
                        }
                    }
                }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(enrollmentAction == "remove"
                     ? (zh ? "这会停止该学校的日历和作息关联，历史记录仍会保留。" : "This stops the school calendar and schedule association. The enrollment history remains.")
                     : (zh ? "这会将当前入学记录标记为已完成，历史记录仍会保留。" : "This marks the enrollment as completed and keeps it in history."))
            }
            .confirmationDialog(zh ? "确认更换学校？" : "Change school?", isPresented: $confirmingSchoolChange, titleVisibility: .visible) {
                Button(zh ? "更换学校并保留历史" : "Change school and keep history") { save() }
                Button(zh ? "取消" : "Cancel", role: .cancel) {}
            } message: {
                Text(zh ? "当前学校记录会结束并保留在历史中，新学校将关联到当前学年。" : "The current school record will be completed and kept in history. The new school will use the current school year.")
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await session.loadSchoolCatalog()
        if let current {
            districtId = current.districtId
            schoolYearId = current.schoolYearId
            gradeCode = current.gradeCode
            await session.loadSchools(districtId: current.districtId)
            schoolId = current.schoolId
            await session.restorePendingSchoolRemoval(childId: child.id)
            await session.restorePendingSchoolChange(childId: child.id)
        } else {
            districtId = session.districts.first?.id ?? ""
            schoolYearId = session.schoolYears.first?.id ?? ""
            if !districtId.isEmpty {
                await session.loadSchools(districtId: districtId)
                schoolId = session.schools.first?.id ?? ""
                gradeCode = selectedSchool?.availableGrades.first ?? ""
            }
        }
    }

    private func save() {
        guard let school = selectedSchool, let year = selectedYear else { return }
        Task {
            if await session.saveEnrollment(child: child, current: current, school: school, schoolYear: year, gradeCode: gradeCode) {
                dismiss()
            }
        }
    }

    private func localizedGrade(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
    }
}

private struct AddChildSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var districtId = ""
    @State private var schoolId = ""
    @State private var gradeCode = ""
    @State private var selectionStatus = ""
    @State private var selectedProgramIds: Set<String> = []
    @FocusState private var isFocused: Bool
    private var zh: Bool { session.usesChinese }
    private var selectedSchool: ParentSchoolDTO? { session.schools.first { $0.id == schoolId } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(zh ? "孩子的称呼" : "Child's name", text: $nickname)
                        .textContentType(.name)
                        .textFieldStyle(MeroliFieldStyle())
                        .focused($isFocused)
                        .submitLabel(.next)
                        .accessibilityIdentifier("meroli.child.nickname")
                }
                Section(zh ? "学校与年级" : "School and grade") {
                    Picker(zh ? "学区" : "District", selection: $districtId) {
                        Text(zh ? "选择学区" : "Choose a district").tag("")
                        ForEach(session.districts) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: districtId) { _, value in
                        schoolId = ""
                        gradeCode = ""
                        selectedProgramIds = []
                        guard !value.isEmpty else { return }
                        Task { await session.loadSchools(districtId: value) }
                    }
                    Picker(zh ? "学校" : "School", selection: $schoolId) {
                        Text(zh ? "选择学校" : "Choose a school").tag("")
                        ForEach(session.schools) { Text($0.name).tag($0.id) }
                    }
                    .disabled(districtId.isEmpty || session.isLoadingSchools)
                    .onChange(of: schoolId) { _, value in
                        gradeCode = ""
                        selectionStatus = ""
                        selectedProgramIds = []
                        if !value.isEmpty { Task { await session.loadTransitionPrograms(schoolId: value) } }
                    }
                    Picker(zh ? "年级" : "Grade", selection: $gradeCode) {
                        Text(zh ? "选择年级" : "Choose a grade").tag("")
                        ForEach(selectedSchool?.availableGrades ?? [], id: \.self) { grade in
                            Text(localizedGrade(grade)).tag(grade)
                        }
                    }
                    .disabled(selectedSchool == nil)
                }
                Section(zh ? "作息项目" : "Schedule programs") {
                    Text(zh ? "选择学校提供的项目；若不确定，可明确选择‘还不确定’。" : "Choose the programs offered by the school, or select Not sure.")
                        .font(.caption).foregroundStyle(MeroliColor.muted)
                    choiceButton("SELECTED", title: zh ? "选择项目" : "Choose programs")
                    choiceButton("NONE", title: zh ? "没有项目" : "No programs")
                    choiceButton("NOT_SURE", title: zh ? "还不确定" : "Not sure")
                    if selectionStatus == "SELECTED" {
                        ForEach(session.transitionPrograms) { program in
                            Button {
                                if selectedProgramIds.contains(program.id) {
                                    selectedProgramIds.remove(program.id)
                                } else {
                                    selectedProgramIds.insert(program.id)
                                }
                            } label: {
                                HStack {
                                    Text(zh && !program.displayNameZh.isEmpty ? program.displayNameZh : program.displayNameEn)
                                    Spacer()
                                    if selectedProgramIds.contains(program.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(MeroliColor.ink)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if session.isSavingChild { ProgressView().padding(.trailing, 7) }
                            Text(zh ? "创建孩子并保存学校资料" : "Create child and save school")
                            Spacer()
                        }
                        .foregroundStyle(.white)
                    }
                    .listRowBackground(MeroliColor.ink)
                    .disabled(session.isSavingChild || selectedSchool == nil || gradeCode.isEmpty
                        || selectionStatus.isEmpty || (selectionStatus == "SELECTED" && selectedProgramIds.isEmpty))
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "新建孩子资料" : "Add a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        isFocused = false
        guard let school = selectedSchool else { return }
        Task {
            if await session.subscribeChild(
                nickname: nickname,
                school: school,
                gradeCode: gradeCode,
                selectionStatus: selectionStatus,
                programIds: selectedProgramIds.sorted()
            ) { dismiss() }
        }
    }

    private func load() async {
        await session.loadSchoolCatalog()
    }

    private func choiceButton(_ value: String, title: String) -> some View {
        Button {
            selectionStatus = value
            if value != "SELECTED" { selectedProgramIds = [] }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selectionStatus == value { Image(systemName: "checkmark.circle.fill") }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionStatus == value ? .isSelected : [])
    }

    private func localizedGrade(_ grade: String) -> String {
        guard zh else { return grade == "K" ? "Kindergarten" : grade }
        switch grade {
        case "PK": return "学前班"
        case "TK": return "过渡幼儿园"
        case "K": return "幼儿园"
        default: return "\(grade) 年级"
        }
    }
}

private struct RenameChildSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let child: ChildDTO
    @State private var nickname: String
    @FocusState private var isFocused: Bool
    private var zh: Bool { session.usesChinese }

    init(child: ChildDTO) {
        self.child = child
        _nickname = State(initialValue: child.nickname)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(zh ? "修改家庭中显示的称呼。" : "Change the name shown for this child in your family.")
                    .font(.body)
                    .foregroundStyle(MeroliColor.muted)
                TextField(zh ? "孩子的称呼" : "Child's name", text: $nickname)
                    .textContentType(.name)
                    .textFieldStyle(MeroliFieldStyle())
                    .focused($isFocused)
                    .accessibilityIdentifier("meroli.child.nickname")
                if let error = session.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral)
                }
                Button {
                    isFocused = false
                    Task { if await session.renameChild(id: child.id, nickname: nickname) { dismiss() } }
                } label: {
                    HStack {
                        if session.isSavingChild { ProgressView().tint(.white) }
                        Text(zh ? "保存" : "Save changes")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 51)
                    .foregroundStyle(.white)
                    .background(MeroliColor.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(session.isSavingChild)
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(MeroliColor.canvas.ignoresSafeArea())
            .navigationTitle(zh ? "编辑称呼" : "Edit name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct SettingsScreen: View {
    @Environment(SessionStore.self) private var session
    @State private var isLoggingOut = false
    @State private var showsDeleteAccount = false
    @State private var appleRawNonce: String?
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            List {
                Section(zh ? "账户" : "Account") {
                    LabeledContent(zh ? "邮箱" : "Email", value: session.email)
                    if session.isAppleLinked {
                        Label(zh ? "已绑定 Apple 账号" : "Apple account linked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MeroliColor.ink)
                    } else {
                        SignInWithAppleButton(.continue, onRequest: { request in
                            let nonce = AppleNonce.generate()
                            appleRawNonce = nonce
                            request.nonce = AppleNonce.sha256(nonce)
                            request.requestedScopes = [.email]
                        }, onCompletion: { result in
                            guard case .success(let authorization) = result,
                                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let tokenData = credential.identityToken,
                                  let token = String(data: tokenData, encoding: .utf8),
                                  let nonce = appleRawNonce else {
                                if case .failure(let error) = result { session.errorMessage = error.localizedDescription }
                                return
                            }
                            Task { await session.bindApple(identityToken: token, rawNonce: nonce) }
                        })
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        .accessibilityIdentifier("meroli.settings.bind-apple")
                    }
                    if let family = session.family, !family.id.isEmpty {
                        LabeledContent(zh ? "家庭编号" : "Family ID", value: family.id)
                    }
                }
                Section(zh ? "语言" : "Language") {
                    Picker(zh ? "应用语言" : "App language", selection: Binding(
                        get: { session.language },
                        set: { value in Task { await session.setLanguage(value) } }
                    )) {
                        Text("English").tag("en")
                        Text("简体中文").tag("zh-CN")
                    }
                }
                if let error = session.errorMessage {
                    Section { Text(error).foregroundStyle(MeroliColor.coral).font(.subheadline) }
                }
                Section {
                    Button(role: .destructive) {
                        isLoggingOut = true
                        Task { await session.logout(); isLoggingOut = false }
                    } label: {
                        HStack {
                            Text(zh ? "退出登录" : "Sign out")
                            Spacer()
                            if isLoggingOut { ProgressView() }
                        }
                    }
                    .disabled(isLoggingOut)
                    .accessibilityIdentifier("meroli.settings.logout")
                }
                Section {
                    Button(role: .destructive) { showsDeleteAccount = true } label: {
                        Text(zh ? "删除账户" : "Delete account")
                    }
                    .accessibilityIdentifier("meroli.settings.delete-account")
                } footer: {
                    Text(zh ? "删除后你将无法再登录。独占家庭的孩子、入学和作息资料会一并删除；其他成员共享的家庭资料会保留。" : "You will no longer be able to sign in. Children, enrollments, and schedules in a family used only by you will be deleted. Shared family data will remain for other members.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "设置" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsDeleteAccount) { DeleteAccountSheet() }
        }
        .task { await session.loadAppleBinding() }
    }
}

private enum AppleNonce {
    static func generate() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct DeleteAccountSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @State private var isDeleting = false
    private var zh: Bool { session.usesChinese }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(zh ? "此操作无法撤销。请输入当前密码，确认删除 Meroli 账户。" : "This action cannot be undone. Enter your current password to confirm deletion of your Meroli account.")
                        .foregroundStyle(MeroliColor.coral)
                    SecureField(zh ? "当前密码" : "Current password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("meroli.delete-account.password")
                }
                if let error = session.errorMessage {
                    Section { Text(error).font(.subheadline).foregroundStyle(MeroliColor.coral) }
                }
                Section {
                    Button(role: .destructive) { confirming = true } label: {
                        HStack {
                            Spacer()
                            if isDeleting { ProgressView().padding(.trailing, 7) }
                            Text(zh ? "永久删除账户" : "Permanently delete account")
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || isDeleting)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MeroliColor.canvas)
            .navigationTitle(zh ? "删除账户" : "Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(zh ? "取消" : "Cancel") { dismiss() } } }
            .confirmationDialog(zh ? "确定永久删除账户？" : "Permanently delete this account?", isPresented: $confirming, titleVisibility: .visible) {
                Button(zh ? "删除账户" : "Delete account", role: .destructive) {
                    isDeleting = true
                    Task {
                        if await session.deleteAccount(password: password) { dismiss() }
                        isDeleting = false
                    }
                }
                Button(zh ? "返回" : "Go back", role: .cancel) {}
            } message: {
                Text(zh ? "删除后无法恢复。系统会先验证当前密码。" : "Deleted information cannot be restored. Your current password will be verified first.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MeroliFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(15)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MeroliColor.line, lineWidth: 1))
    }
}
