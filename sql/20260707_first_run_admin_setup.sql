IF OBJECT_ID(N'dbo.Users_InitAdmin', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Users_InitAdmin;
GO

CREATE PROCEDURE dbo.Users_InitAdmin
    @PasswordHash NVARCHAR(255),
    @Username NVARCHAR(50) = NULL,
    @FullName NVARCHAR(100) = NULL,
    @Phone NVARCHAR(20) = NULL,
    @Email NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @PasswordHash = LTRIM(RTRIM(ISNULL(@PasswordHash, N'')));
    SET @Username = NULLIF(LTRIM(RTRIM(ISNULL(@Username, N''))), N'');
    SET @FullName = NULLIF(LTRIM(RTRIM(ISNULL(@FullName, N''))), N'');
    SET @Phone = NULLIF(LTRIM(RTRIM(ISNULL(@Phone, N''))), N'');
    SET @Email = NULLIF(LTRIM(RTRIM(ISNULL(@Email, N''))), N'');

    IF @PasswordHash = N''
    BEGIN
        RAISERROR(N'Mật khẩu không được để trống.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.Users)
    BEGIN
        SELECT CAST(0 AS INT) AS ResultCode;
        RETURN;
    END

    IF @Username IS NULL
        SET @Username = N'admin';

    IF @FullName IS NULL
        SET @FullName = N'Quản trị viên';

    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Users)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT CAST(0 AS INT) AS ResultCode;
            RETURN;
        END

        DECLARE @AdminRoleId INT;
        SELECT TOP 1 @AdminRoleId = RoleId FROM dbo.Roles WHERE RoleName = N'Admin';

        IF @AdminRoleId IS NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleId = 1)
                SET @AdminRoleId = 1;
            ELSE
                SELECT @AdminRoleId = ISNULL(MAX(RoleId), 0) + 1 FROM dbo.Roles;

            INSERT INTO dbo.Roles (RoleId, RoleName)
            VALUES (@AdminRoleId, N'Admin');
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = N'Nhân viên')
        BEGIN
            DECLARE @EmployeeRoleId INT;
            SELECT @EmployeeRoleId = ISNULL(MAX(RoleId), 0) + 1 FROM dbo.Roles;

            INSERT INTO dbo.Roles (RoleId, RoleName)
            VALUES (@EmployeeRoleId, N'Nhân viên');
        END

        DECLARE @AdminEmpId INT;

        INSERT INTO dbo.employees (name, phone, role_id, email, address, hire_date, is_active)
        VALUES (@FullName, @Phone, @AdminRoleId, @Email, N'Tài khoản quản trị khởi tạo', GETDATE(), 1);

        SET @AdminEmpId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.Users
        (
            Username,
            PasswordHash,
            RoleId,
            employee_id,
            IsActive,
            CreatedAt,
            CanViewImportPrice,
            CanEditImportPrice,
            CanEditSellPrice,
            CanEditStock,
            CanDeleteInvoice,
            CanEditProductInfo,
            CanImportProductExcel,
            CanStocktake,
            CanEditSalesInvoice,
            CanCancelSalesInvoice,
            CanEditPurchaseInvoice,
            CanCancelPurchaseInvoice,
            CanDeletePurchaseInvoice,
            CanDeletePaymentVoucher,
            CanManageCustomers,
            CanManageSuppliers,
            CanManageCatalogs
        )
        VALUES
        (
            @Username,
            @PasswordHash,
            @AdminRoleId,
            @AdminEmpId,
            1,
            GETDATE(),
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            1
        );

        COMMIT TRANSACTION;

        SELECT CAST(1 AS INT) AS ResultCode;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END
GO
