SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Các bản cũ reset bảng rỗng về 0 nên dòng đầu tiên có thể nhận ID 0.
    -- Giữ nguyên dòng 0 để còn đối soát/hủy, chỉ sửa bộ đếm cho các dòng mới.
    IF OBJECT_ID(N'dbo.employee_payrolls', N'U') IS NOT NULL
       AND ISNULL(IDENT_CURRENT(N'dbo.employee_payrolls'), 0) < 1
        DBCC CHECKIDENT ('dbo.employee_payrolls', RESEED, 1) WITH NO_INFOMSGS;

    IF OBJECT_ID(N'dbo.employee_payroll_adjustments', N'U') IS NOT NULL
       AND ISNULL(IDENT_CURRENT(N'dbo.employee_payroll_adjustments'), 0) < 1
        DBCC CHECKIDENT ('dbo.employee_payroll_adjustments', RESEED, 1) WITH NO_INFOMSGS;

    IF OBJECT_ID(N'dbo.employee_payroll_payments', N'U') IS NOT NULL
       AND ISNULL(IDENT_CURRENT(N'dbo.employee_payroll_payments'), 0) < 1
        DBCC CHECKIDENT ('dbo.employee_payroll_payments', RESEED, 1) WITH NO_INFOMSGS;

    IF OBJECT_ID(N'dbo.employee_payroll_payments', N'U') IS NOT NULL
       AND COL_LENGTH(N'dbo.employee_payroll_payments', N'reference_code') IS NOT NULL
    BEGIN
        UPDATE dbo.employee_payroll_payments
        SET reference_code = N'PAYROLL:' + CONVERT(NVARCHAR(20), payment_id)
        WHERE reference_code IS NULL OR LTRIM(RTRIM(reference_code)) = N'';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
