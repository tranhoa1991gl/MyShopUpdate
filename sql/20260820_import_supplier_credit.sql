SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.imports', N'U') IS NULL
        THROW 51000, N'Không tìm thấy bảng dbo.imports.', 1;

    IF COL_LENGTH(N'dbo.imports', N'supplier_credit_applied') IS NULL
    BEGIN
        ALTER TABLE dbo.imports
        ADD supplier_credit_applied DECIMAL(18,0) NOT NULL
            CONSTRAINT DF_imports_supplier_credit_applied DEFAULT(0);
    END;

    IF COL_LENGTH(N'dbo.imports', N'supplier_refund_received') IS NULL
    BEGIN
        ALTER TABLE dbo.imports
        ADD supplier_refund_received DECIMAL(18,0) NOT NULL
            CONSTRAINT DF_imports_supplier_refund_received DEFAULT(0);
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.imports')
          AND definition LIKE N'%supplier_credit_applied%'
    )
    BEGIN
        EXEC sys.sp_executesql N'
ALTER TABLE dbo.imports WITH CHECK
ADD CONSTRAINT CK_imports_supplier_credit_applied_nonnegative
    CHECK (supplier_credit_applied >= 0);';

        ALTER TABLE dbo.imports
        CHECK CONSTRAINT CK_imports_supplier_credit_applied_nonnegative;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.imports')
          AND definition LIKE N'%supplier_refund_received%'
    )
    BEGIN
        EXEC sys.sp_executesql N'
ALTER TABLE dbo.imports WITH CHECK
ADD CONSTRAINT CK_imports_supplier_refund_received_nonnegative
    CHECK (supplier_refund_received >= 0);';

        ALTER TABLE dbo.imports
        CHECK CONSTRAINT CK_imports_supplier_refund_received_nonnegative;
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
