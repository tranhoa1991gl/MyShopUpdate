SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Sửa dữ liệu cũ nếu bảng imports từng bị reseed và sinh import_id = 0.
   Chỉ đổi khóa phiếu; tồn kho, công nợ và số tiền sổ quỹ không bị ghi lại.
*/
IF OBJECT_ID(N'dbo.imports', N'U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.imports WHERE import_id = 0)
BEGIN
    DECLARE @NewImportId INT =
    (
        SELECT ISNULL(MAX(CASE WHEN import_id > 0 THEN import_id END), 0) + 1
        FROM dbo.imports WITH (UPDLOCK, HOLDLOCK)
    );

    SET IDENTITY_INSERT dbo.imports ON;

    INSERT INTO dbo.imports
    (
        import_id,
        import_code,
        employee_id,
        import_date,
        total_amount,
        vat_amount,
        discount,
        final_amount,
        note,
        status,
        supplier_id,
        paid_amount,
        payment_method
    )
    SELECT
        @NewImportId,
        import_code,
        employee_id,
        import_date,
        total_amount,
        vat_amount,
        discount,
        final_amount,
        note,
        status,
        supplier_id,
        paid_amount,
        payment_method
    FROM dbo.imports
    WHERE import_id = 0;

    SET IDENTITY_INSERT dbo.imports OFF;

    IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
        UPDATE dbo.import_details SET import_id = @NewImportId WHERE import_id = 0;

    IF OBJECT_ID(N'dbo.product_serials', N'U') IS NOT NULL
        UPDATE dbo.product_serials SET import_id = @NewImportId WHERE import_id = 0;

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.purchase_returns', N'import_id') IS NOT NULL
        UPDATE dbo.purchase_returns SET import_id = @NewImportId WHERE import_id = 0;

    IF OBJECT_ID(N'dbo.supplier_debt_discount_allocations', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.supplier_debt_discount_allocations', N'import_id') IS NOT NULL
        UPDATE dbo.supplier_debt_discount_allocations
        SET import_id = @NewImportId
        WHERE import_id = 0;

    DELETE FROM dbo.imports WHERE import_id = 0;

    -- IDENTITY_INSERT với giá trị lớn hơn identity hiện tại đã tự đưa
    -- identity hiện hành lên @NewImportId; không cần DBCC CHECKIDENT.
END;

COMMIT TRANSACTION;
