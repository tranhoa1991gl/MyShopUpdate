/* Hotfix 2026-08-09
   Keep cashbook cash-flow categories out of profit calculation.
   Safe to run multiple times. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_categories
    ADD affects_profit BIT NOT NULL
        CONSTRAINT DF_cashbook_categories_affects_profit DEFAULT (1);
END
GO

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NOT NULL
BEGIN
    UPDATE dbo.cashbook_categories
    SET affects_profit = 0
    WHERE category_name IN
    (
        N'Góp vốn',
        N'Thu nợ khách hàng',
        N'Hoàn tiền nhà cung cấp',
        N'Chi trả nhà cung cấp'
    );

    UPDATE dbo.cashbook_categories
    SET affects_profit = 1
    WHERE category_name IN
    (
        N'Thu khác',
        N'Chi khác',
        N'Lương nhân viên',
        N'Tiền điện',
        N'Tiền nước',
        N'Thuê nhà',
        N'Internet',
        N'Vận chuyển',
        N'Văn phòng phẩm'
    );
END
GO
