-- Additive upgrade. Existing rows, financial data and stored procedure signatures stay intact.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.customers', N'U') IS NULL
    THROW 51021, N'Không tìm thấy bảng khách hàng để bổ sung mã số thuế.', 1;

-- Already-upgraded clients need no ALTER permission.
IF COL_LENGTH(N'dbo.customers', N'tax_code') IS NOT NULL RETURN;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @LockResult INT;
    EXEC @LockResult = sys.sp_getapplock
        @Resource = N'HoaTranPOS.CustomerTaxCode.v1',
        @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;
    IF @LockResult < 0
        THROW 51022, N'Chưa thể bổ sung mã số thuế khách hàng. Vui lòng thử lại.', 1;
    IF COL_LENGTH(N'dbo.customers', N'tax_code') IS NULL
        ALTER TABLE dbo.customers ADD tax_code NVARCHAR(50) NULL;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
