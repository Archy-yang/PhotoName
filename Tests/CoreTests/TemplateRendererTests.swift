import XCTest
@testable import PhotoName

final class TemplateRendererTests: XCTestCase {
    private let renderer = TemplateRenderer()

    /// 2026-09-02 10:31:22 本地时间
    private var sampleDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 2
        components.hour = 10; components.minute = 31; components.second = 22
        return Calendar.current.date(from: components)!
    }

    private var fullContext: TemplateContext {
        TemplateContext(
            captureTime: sampleDate,
            cameraModel: "ILCE-7RM5",
            lensModel: "FE 24-70mm F2.8 GM II",
            originalBaseName: "DSC_0001",
            projectName: "Tokyo"
        )
    }

    // MARK: - 日期变量（PRD F-06）

    func test_dateVariables_renderPaddedComponents() throws {
        let output = try renderer.render(RenameTemplate(pattern: "{YYYY}{MM}{DD}_{HH}{mm}{ss}"), context: fullContext, index: 1)
        XCTAssertEqual(output, "20260902_103122")
    }

    func test_monthAndMinute_areCaseSensitive() throws {
        let monthOnly = try renderer.render(RenameTemplate(pattern: "{MM}"), context: fullContext, index: 1)
        let minuteOnly = try renderer.render(RenameTemplate(pattern: "{mm}"), context: fullContext, index: 1)
        XCTAssertEqual(monthOnly, "09")
        XCTAssertEqual(minuteOnly, "31")
    }

    func test_missingCaptureTime_throwsWhenDateVariableUsed() {
        var context = fullContext
        context.captureTime = nil
        XCTAssertThrowsError(
            try renderer.render(RenameTemplate(pattern: "{YYYY}_{index}"), context: context, index: 1)
        ) { error in
            XCTAssertEqual(error as? TemplateError, .missingCaptureTime)
        }
    }

    // MARK: - 其他变量

    func test_index_isZeroPaddedTo4Digits() throws {
        XCTAssertEqual(try renderer.render(RenameTemplate(pattern: "{index}"), context: fullContext, index: 1), "0001")
        XCTAssertEqual(try renderer.render(RenameTemplate(pattern: "{index}"), context: fullContext, index: 42), "0042")
        XCTAssertEqual(try renderer.render(RenameTemplate(pattern: "{index}"), context: fullContext, index: 12345), "12345")
    }

    func test_cameraOriginalProjectVariables() throws {
        let output = try renderer.render(
            RenameTemplate(pattern: "{project}_{YYYY}_{camera}_{original}_{index}"),
            context: fullContext, index: 7
        )
        XCTAssertEqual(output, "Tokyo_2026_ILCE-7RM5_DSC_0001_0007")
    }

    func test_lensVariable() throws {
        let output = try renderer.render(RenameTemplate(pattern: "{lens}_{index}"), context: fullContext, index: 1)
        XCTAssertEqual(output, "FE 24-70mm F2.8 GM II_0001")
    }

    /// 文件名非法字符（路径分隔符等）必须被净化
    func test_cameraModelWithIllegalCharacters_isSanitized() throws {
        var context = fullContext
        context.cameraModel = "X-T5/Mark:II"
        let output = try renderer.render(RenameTemplate(pattern: "{camera}"), context: context, index: 1)
        XCTAssertEqual(output, "X-T5-Mark-II")
    }

    func test_missingProjectName_throwsWhenProjectVariableUsed() {
        var context = fullContext
        context.projectName = nil
        XCTAssertThrowsError(
            try renderer.render(RenameTemplate(pattern: "{project}_{index}"), context: context, index: 1)
        ) { error in
            XCTAssertEqual(error as? TemplateError, .missingProjectName)
        }
    }

    func test_unknownVariable_throws() {
        XCTAssertThrowsError(
            try renderer.render(RenameTemplate(pattern: "{index}_{foo}"), context: fullContext, index: 1)
        ) { error in
            XCTAssertEqual(error as? TemplateError, .unknownVariable("foo"))
        }
    }

    func test_literalTextWithoutVariables_isPreserved() throws {
        let output = try renderer.render(RenameTemplate(pattern: "Wedding-2026"), context: fullContext, index: 1)
        XCTAssertEqual(output, "Wedding-2026")
    }

    // MARK: - 内置预设（PRD F-07）

    func test_builtinPresets_renderWithFullContext() throws {
        for preset in RenameTemplate.builtinPresets {
            let output = try renderer.render(RenameTemplate(pattern: preset.pattern), context: fullContext, index: 3)
            XCTAssertFalse(output.isEmpty, "预设 \(preset.pattern) 渲染结果不应为空")
        }
    }

    func test_builtinPresets_coverExpectedFourPresets() {
        XCTAssertEqual(RenameTemplate.builtinPresets.map(\.pattern), [
            "{YYYY}{MM}{DD}_{index}",
            "{YYYY}{MM}{DD}_{camera}_{index}",
            "{project}_{YYYY}{MM}{DD}_{index}",
            "{project}_{YYYY}{MM}{DD}_{camera}_{index}",
        ])
    }

    // MARK: - 错误文案（UI 直接展示 localizedDescription，必须是可读中文）

    func test_templateErrors_haveReadableLocalizedMessages() {
        XCTAssertEqual(TemplateError.missingCaptureTime.errorDescription, "照片缺少拍摄时间（EXIF），无法使用含日期的模板")
        XCTAssertEqual(TemplateError.missingProjectName.errorDescription, "模板使用了 {project}，请填写项目名")
        XCTAssertEqual(TemplateError.unknownVariable("foo").errorDescription, "模板包含未知变量 {foo}，请检查拼写")
    }
}
