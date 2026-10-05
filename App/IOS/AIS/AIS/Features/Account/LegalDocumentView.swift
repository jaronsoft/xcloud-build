import SwiftUI

enum AISLegalDocument {
    case privacy
    case terms

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .privacy: "account.privacy"
        case .terms: "account.terms"
        }
    }

    var version: String {
        switch self {
        case .privacy: "2026-07"
        case .terms: "2026-07"
        }
    }

    var effectiveDate: String {
        switch self {
        case .privacy: String(localized: "legal.privacy.effective_date")
        case .terms: String(localized: "legal.terms.effective_date")
        }
    }

    var sections: [AISLegalSection] {
        AISLocalization.isChinese ? chineseSections : englishSections
    }

    private var chineseSections: [AISLegalSection] {
        switch self {
        case .terms:
            [
                .init("重要提示", "当您注册、登录、上传素材、购买积分、提交生成任务或继续使用 AIS 服务时，即表示您已阅读、理解并同意本协议。如不同意，请停止使用相关服务。未满十八周岁的用户应在监护人同意后使用。"),
                .init("一、协议范围与服务说明", "本协议适用于 AIS 网站、App、接口以及图片生成、图片编辑、风格模板、视频生成、素材和任务管理等服务。人工智能生成结果可能存在偏差、瑕疵或与预期不一致，平台不承诺结果必然准确、唯一或适合特定用途。"),
                .init("二、账户注册与安全", "您应提供真实、合法、有效的信息并妥善保管账户和验证凭据。不得出租、出借或出售账户，不得绕过验证或以自动化方式滥用服务。发现异常登录或凭据泄露时，应立即修改密码并联系我们。"),
                .init("三、素材上传与个人信息", "您确认对上传的图片、视频、文字、商标、图纸、人物形象等素材拥有合法权利或充分授权。不得上传违法内容、国家秘密、商业秘密或未经授权的信息；非必要不得上传身份证件、人脸、联系方式、财务或医疗等敏感信息。"),
                .init("四、人工智能生成内容与标识", "AIS 生成或编辑的内容属于人工智能生成合成内容。平台会依据适用规则添加显式或隐式标识、文件摘要和追溯记录。您不得恶意删除、篡改、伪造或隐匿依法需要的标识，公开传播时应主动声明其人工智能生成属性。"),
                .init("五、用户行为规范", "不得利用 AIS 制作或传播违法、有害、欺诈、侵权内容，不得冒充他人、虚构权威背书、实施诈骗、攻击系统、绕过安全措施、批量抓取、逆向工程、滥用接口或用于无资质的高风险用途。"),
                .init("六、生成结果与知识产权", "您对自有素材的权利不因使用 AIS 而转移。生成结果能否获得专有权保护取决于法律和具体创作事实。公开发布、商业投放或产品制造前，您应自行完成事实、质量、权利和合规审查。主动推荐至作品广场时，您授予平台展示、适配尺寸和技术分发所必要的非独占许可。"),
                .init("七、积分、付费与退款", "服务可按积分、次数或会员权益计费，提交任务前展示的价格和扣减规则构成交易规则。积分不属于存款或法定货币。任务实际调用模型后可能产生不可逆成本；平台故障导致的明确失败按页面规则退还，审美差异或结果未达到主观预期不当然构成退款理由。"),
                .init("八、数据保存、追溯与安全", "平台在任务查询、资产管理、安全防护、计费、投诉与合规所必要的期限内保存相关数据，并采取与风险相适应的安全措施。为履行追溯义务，可记录内容编号、任务与资产关系、生成参数、文件摘要、标识策略和操作日志。"),
                .init("九、第三方服务", "AIS 可能使用云存储、支付、内容分发和人工智能模型等第三方服务。第三方服务受其条款、隐私规则、可用性和地域限制约束；平台会在合理范围内协助处理超出平台控制的中断或变更。"),
                .init("十、服务变更与终止", "平台可因法律政策、安全风险、模型能力或产品升级调整服务、价格、额度和规则。违反本协议或危害他人及平台安全时，平台可采取警告、限制生成、下架、冻结账户、终止服务、保存证据或报告主管机关等措施。"),
                .init("十一、责任限制", "除法律明确规定外，平台不对模型固有不确定性、用户违法使用、未经审查的商业投放、第三方异常或不可抗力造成的间接损失承担超出法定范围的责任。本条不排除依法不得限制的消费者权益和其他责任。"),
                .init("十二、更新与争议解决", "平台可依据法律和服务变化更新协议并标注版本和生效日期。协议适用中华人民共和国法律；争议应先友好协商，协商不成的，可依法向有管辖权的人民法院提起诉讼。"),
                .init("十三、联系我们", "如对本协议、内容标识、账户、付费或权利投诉有疑问，请联系 ais@get-free.net，并提供必要的任务编号、内容编号或证明材料。"),
            ]
        case .privacy:
            [
                .init("重要提示", "本政策说明 AIS 如何收集、使用、存储、共享和保护您的个人信息。请在使用账户登录、素材上传、人工智能生成、支付或分享功能前仔细阅读。"),
                .init("一、适用范围与运营方", "本政策适用于 AIS 产品智造网站与 iOS App。由 Wekare Partners LLC 在美国发行，中国境内发行商、运营方、技术方为 扬州市佳融信息技术有限公司（佳融软件）。服务可能依据您所在区域由相应主体或受托服务商提供。"),
                .init("二、我们收集的信息", "账户与认证信息包括邮箱、昵称、登录凭据标识和会话记录；创作信息包括您主动上传的图片、文字要求、模板参数、生成结果和任务记录；交易信息包括积分余额、会员状态、订单与流水；设备与诊断信息包括系统版本、App 版本、网络状态、故障和安全日志。我们不会在公开分享详情中披露 Prompt、内部模型配置或原始 JSON。"),
                .init("三、使用目的", "我们使用相关信息完成身份验证、保持登录、上传和处理素材、生成内容、展示任务与资产、计算和核验积分、处理支付退款、提供客服、安全防护、故障诊断、履行生成内容标识与法定义务。"),
                .init("四、相册、剪贴板与本地缓存", "只有在您主动选择图片时才请求相册访问。选中的待创作图片会先保存在本地内存，确认 AI 识图或生成后才上传。分享作品时会按您的操作复制公开链接到剪贴板。模型、分类、任务和图片可缓存在本机以提升体验并减少流量，您可在“我的”中清理缓存。"),
                .init("五、人工智能与第三方处理", "为完成服务，我们可能向受约束的人工智能模型、云计算、对象存储、内容分发、登录、支付和诊断服务商传输必要数据。我们要求服务商仅按约定目的处理，并采取合理的安全和保密措施。"),
                .init("六、公开分享与作品广场", "只有在您主动开启分享或允许推荐时，作品及必要规格才会公开。公开信息可能包括标题、描述、参考素材、成果、尺寸、比例、文件大小、耗时和点数，不包含 Prompt、内部模型信息和原始响应。公开链接可被获得链接的任何人访问，关闭分享后将停止新的公开访问，但他人已保存的副本不受控制。"),
                .init("七、存储期限与安全", "我们仅在实现服务、履行合同、安全审计、争议处理或法定义务所需期限内保存信息。登录刷新凭据采用受保护存储并按活动期限轮换；传输使用 HTTPS；本地会话存入 Keychain。互联网服务无法保证绝对安全，发生可能影响您权益的事件时我们会依法处置和通知。"),
                .init("八、跨境与区域处理", "服务可能使用位于您所在国家或地区之外的基础设施或技术服务。发生跨境处理时，我们将依据适用法律采取合同、安全评估、单独同意或其他必要措施，并尽量减少传输的数据范围。"),
                .init("九、您的权利", "您可在产品功能或通过联系我们访问、更正、复制、删除相关信息，撤回作品广场偏好、退出登录、清理本地缓存或申请注销账户。注销会清理依法无需继续保存的成果与信息且不可恢复；法定留存、争议处理和安全审计记录除外。"),
                .init("十、未成年人", "未满十八周岁的用户应在监护人指导下使用。若发现未经适当授权收集了未成年人的信息，请联系我们，我们会依法核实和处理。"),
                .init("十一、更新与联系", "我们会因功能、数据处理或法律变化更新本政策，并标注新版本和生效日期。重大变化会通过显著方式提示。如有隐私问题或权利请求，请联系 ais@get-free.net。"),
            ]
        }
    }

    private var englishSections: [AISLegalSection] {
        switch self {
        case .terms:
            [
                .init("Important Notice", "By registering, signing in, uploading materials, purchasing points, submitting a generation task, or continuing to use AIS, you acknowledge and agree to these Terms. Users under 18 must use the service with guardian consent."),
                .init("1. Scope and Services", "These Terms cover the AIS website, iOS app, APIs, image and video generation, editing, templates, assets, and task management. AI output may be inaccurate, incomplete, defective, or unsuitable for a particular purpose."),
                .init("2. Accounts and Security", "Provide valid information and protect your credentials. Do not sell, rent, lend, automate, or bypass verification for an account. Notify us promptly of suspected compromise."),
                .init("3. Uploaded Materials", "You must own or have sufficient permission for all uploaded images, text, marks, drawings, likenesses, and other materials. Do not upload unlawful, confidential, or unnecessarily sensitive personal information."),
                .init("4. AI-Generated Content Labels", "AIS may attach visible or machine-readable labels, file digests, and traceability records required by applicable rules. You must not maliciously remove, falsify, or conceal required labels and should disclose the AI-generated nature when distributing content."),
                .init("5. Acceptable Use", "Do not create unlawful, harmful, deceptive, infringing, impersonating, or fraudulent content; attack or circumvent security; scrape at scale; reverse engineer; abuse APIs; or use AIS for regulated high-risk purposes without required authorization."),
                .init("6. Output and Intellectual Property", "You retain rights in your own materials. Protection and permitted use of generated output depend on applicable law and the facts. You are responsible for factual, quality, rights, and compliance review before publication or commercial use."),
                .init("7. Points, Payment, and Refunds", "Services may be charged by points, usage, or membership. Displayed pricing and deduction rules apply to each transaction. Points are not deposits or legal tender. Clear platform failures may be refunded under displayed rules; subjective dissatisfaction alone does not guarantee a refund."),
                .init("8. Retention, Traceability, and Security", "We retain data as needed for service delivery, assets, billing, security, complaints, and legal compliance. Traceability records may include content IDs, task-asset relationships, generation parameters, file digests, label policies, and audit logs."),
                .init("9. Third-Party Services", "AIS may rely on cloud, storage, payment, delivery, and AI providers subject to their own availability, regional limits, and terms."),
                .init("10. Changes and Termination", "We may update services, prices, quotas, and rules for legal, safety, operational, or technical reasons. Violations may result in warnings, restrictions, content removal, suspension, termination, evidence preservation, or reports to authorities."),
                .init("11. Liability", "To the extent permitted by law, AIS is not responsible beyond mandatory legal obligations for indirect loss caused by model uncertainty, unlawful use, unreviewed commercial use, third-party failures, or force majeure."),
                .init("12. Updates and Disputes", "We may revise these Terms with a new version and effective date. The Terms are governed by the laws of the People’s Republic of China, subject to mandatory consumer protections and jurisdiction rules."),
                .init("13. Contact", "For questions about these Terms, content labels, accounts, billing, or rights complaints, contact ais@get-free.net with relevant task or content identifiers."),
            ]
        case .privacy:
            [
                .init("Important Notice", "This Policy explains how AIS collects, uses, stores, shares, and protects personal information across account, upload, AI processing, payment, sharing, and support features."),
                .init("1. Scope and Operators", "This Policy applies to the AIS website and iOS app. It is published in the United States by Wekare Partners LLC, with Yangzhou Jiarong Information Technology Co., Ltd. (JaronSoft LLC) serving as the publisher, operator, and technical provider within mainland China."),
                .init("2. Information We Process", "We process account and session data; materials, instructions, parameters, outputs, and task records you submit; points, membership, orders, and transactions; and limited device, network, crash, security, and diagnostic data. Public share details exclude prompts, internal model configuration, and raw JSON."),
                .init("3. Purposes", "We use information to authenticate and maintain sessions, upload and process materials, generate content, manage tasks and assets, calculate and verify points, process payments and refunds, provide support, protect security, diagnose failures, label generated content, and meet legal obligations."),
                .init("4. Photos, Clipboard, and Cache", "Photo access is requested only when you choose an image. Pending images remain local until AI analysis or generation is confirmed. Sharing copies the public link to the clipboard at your direction. Local caches reduce load time and traffic and can be cleared in Account."),
                .init("5. AI and Service Providers", "Necessary information may be sent to contracted AI, cloud, object storage, content delivery, identity, payment, and diagnostics providers. They are required to process it only for agreed purposes with appropriate safeguards."),
                .init("6. Public Sharing", "A work becomes public only when you enable sharing or gallery recommendation. Public fields may include title, description, reference materials, result, dimensions, ratio, file size, duration, and point cost, but never prompts, internal model data, or raw responses."),
                .init("7. Retention and Security", "We retain information only as needed for service delivery, contracts, security, disputes, and legal duties. Transport uses HTTPS and iOS session credentials are held in Keychain. No internet service can guarantee absolute security."),
                .init("8. International Processing", "Infrastructure and providers may process data outside your region. Where required, we apply contractual, assessment, consent, or other safeguards and minimize the data transferred."),
                .init("9. Your Choices and Rights", "You may request access, correction, copies, deletion, withdraw gallery preferences, sign out, clear cache, or request account deletion. Required legal, dispute, and security records may be retained."),
                .init("10. Children", "Users under 18 should use AIS with guardian guidance. Contact us if you believe a minor’s information was collected without appropriate authorization."),
                .init("11. Updates and Contact", "We may update this Policy as features, processing, or laws change and will identify the version and effective date. Contact ais@get-free.net for privacy questions or rights requests."),
            ]
        }
    }
}

struct AISLegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String

    init(_ title: String, _ body: String) {
        self.title = title
        self.body = body
    }
}

struct LegalDocumentView: View {
    let document: AISLegalDocument

    var body: some View {
        ZStack {
            AISPageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.localizedTitle)
                            .font(.largeTitle.bold())
                        Text(
                            String(
                                format: String(localized: "legal.version_and_date"),
                                document.version,
                                document.effectiveDate
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .aisSurface(cornerRadius: 24)

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .aisSurface(cornerRadius: 20)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(document.localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("LegalDocumentView") {
    NavigationStack {
        LegalDocumentView(document: .privacy)
    }
}
