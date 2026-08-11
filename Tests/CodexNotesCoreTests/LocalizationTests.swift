import Foundation
import XCTest
@testable import CodexNotesCore

final class LocalizationTests: XCTestCase {
    func testLanguagePreferenceDefaultsToSystemWhenMissing() {
        withDefaults { defaults in
            XCTAssertNil(defaults.object(forKey: AppLanguagePreference.key))
            XCTAssertEqual(AppLanguagePreference.load(from: defaults), .system)
            XCTAssertNil(defaults.object(forKey: AppLanguagePreference.key))
        }
    }

    func testLanguagePreferenceNormalizesAndRepairsInvalidStoredValue() {
        XCTAssertEqual(AppLanguagePreference.normalized("unsupported"), .system)

        withDefaults { defaults in
            defaults.set("unsupported", forKey: AppLanguagePreference.key)

            XCTAssertEqual(AppLanguagePreference.load(from: defaults), .system)
            XCTAssertEqual(
                defaults.string(forKey: AppLanguagePreference.key),
                AppLanguagePreference.system.rawValue
            )
        }
    }

    func testLanguagePreferenceRoundTripsEverySupportedChoice() {
        withDefaults { defaults in
            for preference in AppLanguagePreference.allCases {
                AppLanguagePreference.save(preference, to: defaults)
                XCTAssertEqual(AppLanguagePreference.load(from: defaults), preference)
                XCTAssertEqual(
                    defaults.string(forKey: AppLanguagePreference.key),
                    preference.rawValue
                )
            }
        }
    }

    func testLanguageOptionsHaveStableOrderAndLocalizedLabels() {
        XCTAssertEqual(
            AppLanguagePreference.allCases,
            [.system, .simplifiedChinese, .english]
        )

        let keys: [L10n.Key] = [
            .languageSystem,
            .languageSimplifiedChinese,
            .languageEnglish,
        ]
        XCTAssertEqual(
            keys.map { localization(.simplifiedChinese).text($0) },
            ["跟随系统", "简体中文", "English"]
        )
        XCTAssertEqual(
            keys.map { localization(.english).text($0) },
            ["System", "简体中文", "English"]
        )
    }

    func testL10nAllowsAnExplicitLanguagePreference() {
        XCTAssertEqual(
            L10n.text(.settingsGeneralTitle, preference: .simplifiedChinese),
            "通用"
        )
        XCTAssertEqual(
            L10n.text(.settingsGeneralTitle, preference: .english),
            "General"
        )
    }

    func testManualLanguageChoicesOverrideSystemPreferences() {
        XCTAssertEqual(
            AppLocalization.resolve(.simplifiedChinese, preferredLanguages: ["en-US"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLocalization.resolve(.english, preferredLanguages: ["zh-Hans-CN"]),
            .en
        )
    }

    func testSystemLanguageRecognizesRegionsAndSupportedFallbackPreferences() {
        XCTAssertEqual(
            AppLocalization.resolve(.system, preferredLanguages: ["zh-Hans-CN"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLocalization.resolve(.system, preferredLanguages: ["zh-Hant-TW"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLocalization.resolve(.system, preferredLanguages: ["en-GB"]),
            .en
        )
        XCTAssertEqual(
            AppLocalization.resolve(.system, preferredLanguages: ["fr-FR", "en-US"]),
            .en
        )
        XCTAssertEqual(
            AppLocalization.resolve(.system, preferredLanguages: ["fr-FR"]),
            .zhHans
        )
    }

    func testBothLanguagesContainExactlyEveryDeclaredKey() throws {
        let declared = Set(L10n.Key.allCases.map(\.rawValue))
        let chinese = try localizedStrings(for: .zhHans)
        let english = try localizedStrings(for: .en)

        XCTAssertEqual(Set(chinese.keys), declared)
        XCTAssertEqual(Set(english.keys), declared)
        XCTAssertEqual(Set(chinese.keys), Set(english.keys))
    }

    func testBothLanguagesUseMatchingNamedTokensForEveryKey() throws {
        let chinese = try localizedStrings(for: .zhHans)
        let english = try localizedStrings(for: .en)

        for key in L10n.Key.allCases {
            XCTAssertEqual(
                namedTokens(in: chinese[key.rawValue] ?? ""),
                namedTokens(in: english[key.rawValue] ?? ""),
                "Token mismatch for \(key.rawValue)"
            )
        }
    }

    func testEveryKeyResolvesWithoutLeakingItsIdentifier() {
        let chinese = localization(.simplifiedChinese)
        let english = localization(.english)

        for key in L10n.Key.allCases {
            XCTAssertNotEqual(chinese.text(key), key.rawValue, key.rawValue)
            XCTAssertNotEqual(english.text(key), key.rawValue, key.rawValue)
        }
    }

    func testCriticalCopyAndMarkdownAltTextAreLanguageSpecific() {
        let chinese = localization(.simplifiedChinese)
        let english = localization(.english)

        XCTAssertEqual(chinese.text(.languageSystem), "跟随系统")
        XCTAssertEqual(english.text(.languageSystem), "System")
        XCTAssertEqual(chinese.text(.noteScopeTask), "任务笔记")
        XCTAssertEqual(english.text(.noteScopeTask), "Task Note")
        XCTAssertEqual(chinese.text(.imageMarkdownAltText), "图片")
        XCTAssertEqual(english.text(.imageMarkdownAltText), "Image")
        XCTAssertEqual(chinese.text(.settingsEditorTitle), "编辑器")
        XCTAssertEqual(english.text(.settingsEditorTitle), "Editor")
        XCTAssertEqual(
            chinese.text(.settingsEditorWindowResizeHint),
            "拖动笔记窗口边缘可调整大小，尺寸会自动记住。"
        )
        XCTAssertEqual(
            english.text(.settingsEditorWindowResizeHint),
            "Drag a note window edge to resize. CodexNotes remembers the size."
        )
        XCTAssertEqual(chinese.text(.settingsGeneralTitle), "通用")
        XCTAssertEqual(english.text(.settingsGeneralTitle), "General")
        XCTAssertEqual(chinese.text(.settingsLanguageTitle), "语言")
        XCTAssertEqual(english.text(.settingsLanguageTitle), "Language")
        XCTAssertEqual(chinese.text(.settingsLaunchAtLoginTitle), "登录时启动")
        XCTAssertEqual(english.text(.settingsLaunchAtLoginTitle), "Launch at Login")
        XCTAssertEqual(chinese.text(.settingsAboutTitle), "关于 CodexNotes")
        XCTAssertEqual(english.text(.settingsAboutTitle), "About CodexNotes")
        XCTAssertEqual(chinese.text(.settingsAboutGitHub), "GitHub 项目")
        XCTAssertEqual(english.text(.settingsAboutGitHub), "GitHub Project")
        XCTAssertEqual(chinese.text(.settingsAboutX), "X：关注作者")
        XCTAssertEqual(english.text(.settingsAboutX), "X: Follow the Author")
        XCTAssertEqual(chinese.text(.settingsAboutCoffee), "☕ 请江sir喝杯咖啡")
        XCTAssertEqual(english.text(.settingsAboutCoffee), "☕ Buy Me a Coffee")
        XCTAssertEqual(chinese.text(.settingsAboutFeedbackEmail), "反馈邮箱")
        XCTAssertEqual(english.text(.settingsAboutFeedbackEmail), "Feedback")
        XCTAssertEqual(chinese.text(.settingsAboutCopyEmail), "复制邮箱地址")
        XCTAssertEqual(english.text(.settingsAboutCopyEmail), "Copy Email Address")
        XCTAssertEqual(chinese.text(.settingsAboutEmailCopied), "已复制")
        XCTAssertEqual(english.text(.settingsAboutEmailCopied), "Copied")
        XCTAssertEqual(chinese.text(.settingsAboutAutomaticCheck), "自动检查更新")
        XCTAssertEqual(
            english.text(.settingsAboutAutomaticCheck),
            "Automatically Check for Updates"
        )
        XCTAssertEqual(
            chinese.text(.settingsAboutAutomaticCheckDescription),
            "每天检查一次；网络失败会稍后重试，仅发现新版本时提示。"
        )
        XCTAssertEqual(
            english.text(.settingsAboutAutomaticCheckDescription),
            "Check once a day; retry later after a network failure, and notify only for new versions."
        )
        XCTAssertEqual(
            chinese.text(
                .appUpdateBannerAvailable,
                replacements: ["version": "1.5.0"]
            ),
            "CodexNotes 1.5.0 现已可用"
        )
        XCTAssertEqual(
            english.text(
                .appUpdateBannerAvailable,
                replacements: ["version": "1.5.0"]
            ),
            "CodexNotes 1.5.0 is available"
        )
        XCTAssertEqual(
            chinese.text(.settingsLaunchAtLoginError),
            "无法更改登录启动设置，请重试。"
        )
        XCTAssertEqual(
            english.text(.settingsLaunchAtLoginError),
            "Couldn’t change the launch-at-login setting. Try again."
        )
        XCTAssertEqual(chinese.text(.statusItemQuit), "退出 CodexNotes")
        XCTAssertEqual(english.text(.statusItemQuit), "Quit CodexNotes")
    }

    func testNamedTokensAllowLanguageSpecificWordOrderAndPreserveUnknownTokens() {
        let chinese = localization(.simplifiedChinese)
        let english = localization(.english)

        XCTAssertEqual(
            chinese.text(
                .moveSelectionActionToEnd,
                replacements: ["scope": "项目笔记", "name": "示例"]
            ),
            "移到项目笔记「示例」末尾"
        )
        XCTAssertEqual(
            english.text(
                .moveSelectionActionToEnd,
                replacements: ["scope": "Project Note", "name": "Example"]
            ),
            "Move to the end of Project Note “Example”"
        )
        XCTAssertEqual(
            english.text(.connectionHelpFollowing),
            "Following the current Codex task: {task}"
        )
    }

    private func localization(_ preference: AppLanguagePreference) -> AppLocalization {
        AppLocalization(
            preference: preference,
            resourceBundle: AppLocalization.defaultResourceBundle,
            preferredLanguages: []
        )
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func localizedStrings(
        for language: ResolvedAppLanguage
    ) throws -> [String: String] {
        guard let resourceURL = AppLocalization.defaultResourceBundle.resourceURL else {
            XCTFail("Missing resource bundle URL")
            return [:]
        }
        let stringsURL = resourceURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings", isDirectory: false)
        let data = try Data(contentsOf: stringsURL)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )
        return try XCTUnwrap(value as? [String: String])
    }

    private func namedTokens(in template: String) -> Set<String> {
        let expression = try! NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9_]*)\}"#)
        let range = NSRange(template.startIndex..., in: template)
        return Set(expression.matches(in: template, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: template) else { return nil }
            return String(template[tokenRange])
        })
    }
}
