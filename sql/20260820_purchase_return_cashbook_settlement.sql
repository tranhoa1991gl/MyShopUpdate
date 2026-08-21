SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NULL
        THROW 51000, N'Không tìm thấy bảng dbo.purchase_returns.', 1;

    IF COL_LENGTH(N'dbo.purchase_returns', N'settlement_type') IS NULL
    BEGIN
        ALTER TABLE dbo.purchase_returns
        ADD settlement_type NVARCHAR(20) NOT NULL
            CONSTRAINT DF_purchase_returns_settlement_type DEFAULT (N'DEBT_OFFSET');
    END;

    IF COL_LENGTH(N'dbo.purchase_returns', N'refund_method') IS NULL
        ALTER TABLE dbo.purchase_returns ADD refund_method NVARCHAR(50) NULL;

    EXEC sys.sp_executesql N'
UPDATE dbo.purchase_returns
SET settlement_type = N''DEBT_OFFSET''
WHERE settlement_type IS NULL
   OR settlement_type NOT IN (N''DEBT_OFFSET'', N''REFUND'');

UPDATE dbo.purchase_returns
SET refund_method = NULL
WHERE settlement_type = N''DEBT_OFFSET'';';

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints cc
        WHERE cc.parent_object_id = OBJECT_ID(N'dbo.purchase_returns')
          AND cc.definition LIKE N'%settlement_type%'
    )
    BEGIN
        EXEC sys.sp_executesql N'
ALTER TABLE dbo.purchase_returns WITH CHECK
ADD CONSTRAINT CK_purchase_returns_settlement_type
    CHECK (settlement_type IN (N''DEBT_OFFSET'', N''REFUND''));
ALTER TABLE dbo.purchase_returns CHECK CONSTRAINT CK_purchase_returns_settlement_type;';
    END;

    IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.cashbook_categories
            WHERE category_type = N'IN'
              AND category_name = N'Thu hoàn tiền hàng trả NCC'
        )
        BEGIN
            IF COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NOT NULL
                UPDATE dbo.cashbook_categories
                SET is_system = 1,
                    is_active = 1,
                    affects_profit = 0,
                    sort_order = 35
                WHERE category_type = N'IN'
                  AND category_name = N'Thu hoàn tiền hàng trả NCC';
            ELSE
                UPDATE dbo.cashbook_categories
                SET is_system = 1,
                    is_active = 1,
                    sort_order = 35
                WHERE category_type = N'IN'
                  AND category_name = N'Thu hoàn tiền hàng trả NCC';
        END
        ELSE
        BEGIN
            IF COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NOT NULL
                INSERT INTO dbo.cashbook_categories
                    (category_type, category_name, is_system, is_active, affects_profit, sort_order)
                VALUES
                    (N'IN', N'Thu hoàn tiền hàng trả NCC', 1, 1, 0, 35);
            ELSE
                INSERT INTO dbo.cashbook_categories
                    (category_type, category_name, is_system, is_active, sort_order)
                VALUES
                    (N'IN', N'Thu hoàn tiền hàng trả NCC', 1, 1, 35);
        END;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

CREATE OR ALTER PROCEDURE dbo.PurchaseReturnHistory_GetReturns
    @FromDate DATETIME,
    @ToDate DATETIME,
    @Keyword NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    SELECT
        pr.return_id AS ReturnId,
        pr.return_code AS ReturnCode,
        pr.import_id AS ImportId,
        ISNULL(i.import_code, N'') AS ImportCode,
        pr.supplier_id AS SupplierId,
        ISNULL(s.supplier_name, N'') AS SupplierName,
        pr.employee_id AS EmployeeId,
        ISNULL(e.name, ISNULL(u.Username, N'')) AS EmployeeName,
        pr.return_date AS ReturnDate,
        ISNULL(pr.total_amount, 0) AS TotalAmount,
        ISNULL(pr.note, N'') AS Note,
        ISNULL(pr.status, N'') AS Status,
        ISNULL(pr.settlement_type, N'DEBT_OFFSET') AS SettlementType,
        ISNULL(pr.refund_method, N'') AS RefundMethod,
        CASE
            WHEN ISNULL(pr.settlement_type, N'DEBT_OFFSET') = N'REFUND'
                THEN N'Nhận lại tiền - ' + ISNULL(NULLIF(pr.refund_method, N''), N'Tiền mặt')
            ELSE N'Cấn trừ công nợ'
        END AS SettlementText,
        CASE
            WHEN ISNULL(pr.status, N'') IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy') THEN N'Đã hủy'
            ELSE N'Hoàn tất'
        END AS StatusText
    FROM dbo.purchase_returns pr
    LEFT JOIN dbo.imports i ON i.import_id = pr.import_id
    LEFT JOIN dbo.suppliers s ON s.supplier_id = pr.supplier_id
    LEFT JOIN dbo.employees e ON e.employee_id = pr.employee_id
    LEFT JOIN dbo.Users u ON u.employee_id = pr.employee_id
    WHERE pr.return_date BETWEEN @FromDate AND @ToDate
      AND (
            @Keyword = N''
            OR pr.return_code LIKE N'%' + @Keyword + N'%'
            OR ISNULL(i.import_code, N'') LIKE N'%' + @Keyword + N'%'
            OR ISNULL(s.supplier_name, N'') LIKE N'%' + @Keyword + N'%'
            OR ISNULL(pr.note, N'') LIKE N'%' + @Keyword + N'%'
          )
    ORDER BY pr.return_date DESC, pr.return_id DESC;
END;
GO
