SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Chuẩn hóa NCC có supplier_id = 0 do CSDL cũ từng bị reseed identity.
   Không tự gộp theo tên vì hai NCC khác nhau có thể trùng tên hợp lệ.
*/
IF OBJECT_ID(N'dbo.suppliers', N'U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.suppliers WHERE supplier_id = 0)
BEGIN
    DECLARE @NewSupplierId INT =
    (
        SELECT ISNULL(MAX(CASE WHEN supplier_id > 0 THEN supplier_id END), 0) + 1
        FROM dbo.suppliers WITH (UPDLOCK, HOLDLOCK)
    );

    SET IDENTITY_INSERT dbo.suppliers ON;

    INSERT INTO dbo.suppliers
    (
        supplier_id,
        supplier_name,
        phone,
        address,
        email,
        tax_code,
        bank_code,
        bank_name,
        bank_account,
        bank_owner,
        is_active
    )
    SELECT
        @NewSupplierId,
        supplier_name,
        phone,
        address,
        email,
        tax_code,
        bank_code,
        bank_name,
        bank_account,
        bank_owner,
        is_active
    FROM dbo.suppliers
    WHERE supplier_id = 0;

    SET IDENTITY_INSERT dbo.suppliers OFF;

    IF OBJECT_ID(N'dbo.imports', N'U') IS NOT NULL
        UPDATE dbo.imports SET supplier_id = @NewSupplierId WHERE supplier_id = 0;

    IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
        UPDATE dbo.supplier_payments SET supplier_id = @NewSupplierId WHERE supplier_id = 0;

    IF OBJECT_ID(N'dbo.supplier_debt_adjustments', N'U') IS NOT NULL
        UPDATE dbo.supplier_debt_adjustments SET supplier_id = @NewSupplierId WHERE supplier_id = 0;

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.purchase_returns', N'supplier_id') IS NOT NULL
        UPDATE dbo.purchase_returns SET supplier_id = @NewSupplierId WHERE supplier_id = 0;

    DELETE FROM dbo.suppliers WHERE supplier_id = 0;
END;

COMMIT TRANSACTION;
