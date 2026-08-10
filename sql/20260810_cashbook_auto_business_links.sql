/* Feature 2026-08-10
   Link sales/purchase/debt payments to Cashbook without double-counting profit.
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
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.cashbook_categories
        WHERE category_type = N'IN'
          AND category_name = N'Thu tiền khách trả'
    )
    BEGIN
        INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, affects_profit, sort_order)
        VALUES (N'IN', N'Thu tiền khách trả', 1, 1, 0, 25);
    END

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.cashbook_categories
        WHERE category_type = N'OUT'
          AND category_name = N'Chi tiền trả NCC'
    )
    BEGIN
        INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, is_active, affects_profit, sort_order)
        VALUES (N'OUT', N'Chi tiền trả NCC', 1, 1, 0, 85);
    END

    UPDATE dbo.cashbook_categories
    SET affects_profit = 0
    WHERE category_name IN
    (
        N'Góp vốn',
        N'Thu tiền khách trả',
        N'Thu nợ khách hàng',
        N'Hoàn tiền nhà cung cấp',
        N'Chi trả nhà cung cấp',
        N'Chi tiền trả NCC'
    );
END
GO

IF OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = N'IX_cashbook_entries_reference_code'
          AND object_id = OBJECT_ID(N'dbo.cashbook_entries')
   )
BEGIN
    CREATE INDEX IX_cashbook_entries_reference_code
    ON dbo.cashbook_entries(reference_code, is_deleted)
    INCLUDE (entry_type, category_name, amount);
END
GO
