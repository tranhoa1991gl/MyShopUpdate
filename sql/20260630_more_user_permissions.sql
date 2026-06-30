IF COL_LENGTH(N'dbo.Users', N'CanEditSalesInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditSalesInvoice BIT NOT NULL CONSTRAINT DF_Users_CanEditSalesInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanCancelSalesInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanCancelSalesInvoice BIT NOT NULL CONSTRAINT DF_Users_CanCancelSalesInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanEditPurchaseInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditPurchaseInvoice BIT NOT NULL CONSTRAINT DF_Users_CanEditPurchaseInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanCancelPurchaseInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanCancelPurchaseInvoice BIT NOT NULL CONSTRAINT DF_Users_CanCancelPurchaseInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanDeletePurchaseInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanDeletePurchaseInvoice BIT NOT NULL CONSTRAINT DF_Users_CanDeletePurchaseInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanDeletePaymentVoucher') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanDeletePaymentVoucher BIT NOT NULL CONSTRAINT DF_Users_CanDeletePaymentVoucher DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanManageCustomers') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanManageCustomers BIT NOT NULL CONSTRAINT DF_Users_CanManageCustomers DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanManageSuppliers') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanManageSuppliers BIT NOT NULL CONSTRAINT DF_Users_CanManageSuppliers DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanManageCatalogs') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanManageCatalogs BIT NOT NULL CONSTRAINT DF_Users_CanManageCatalogs DEFAULT (0);
END
GO

UPDATE u
SET
    CanViewImportPrice = 1,
    CanEditImportPrice = 1,
    CanEditSellPrice = 1,
    CanEditStock = 1,
    CanDeleteInvoice = 1,
    CanEditProductInfo = 1,
    CanImportProductExcel = 1,
    CanStocktake = 1,
    CanEditSalesInvoice = 1,
    CanCancelSalesInvoice = 1,
    CanEditPurchaseInvoice = 1,
    CanCancelPurchaseInvoice = 1,
    CanDeletePurchaseInvoice = 1,
    CanDeletePaymentVoucher = 1,
    CanManageCustomers = 1,
    CanManageSuppliers = 1,
    CanManageCatalogs = 1
FROM dbo.Users u
INNER JOIN dbo.Roles r ON u.RoleId = r.RoleId
WHERE r.RoleName = N'Admin' OR u.Username = N'admin';
GO

IF OBJECT_ID(N'dbo.Users_AllWithRole', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Users_AllWithRole;
GO

CREATE PROCEDURE dbo.Users_AllWithRole
AS
BEGIN
    SELECT
        u.UserId,
        u.Username,
        u.PasswordHash,
        u.RoleId,
        r.RoleName,
        u.IsActive,
        u.CreatedAt,
        u.employee_id AS EmployeeId,
        u.CanViewImportPrice,
        u.CanEditImportPrice,
        u.CanEditSellPrice,
        u.CanEditStock,
        u.CanDeleteInvoice,
        u.CanEditProductInfo,
        u.CanImportProductExcel,
        u.CanStocktake,
        u.CanEditSalesInvoice,
        u.CanCancelSalesInvoice,
        u.CanEditPurchaseInvoice,
        u.CanCancelPurchaseInvoice,
        u.CanDeletePurchaseInvoice,
        u.CanDeletePaymentVoucher,
        u.CanManageCustomers,
        u.CanManageSuppliers,
        u.CanManageCatalogs,
        e.name AS EmployeeName
    FROM dbo.Users u
    INNER JOIN dbo.Roles r ON u.RoleId = r.RoleId
    LEFT JOIN dbo.employees e ON u.employee_id = e.employee_id;
END
GO

IF OBJECT_ID(N'dbo.Users_ByUsername', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Users_ByUsername;
GO

CREATE PROCEDURE dbo.Users_ByUsername
    @Username NVARCHAR(50)
AS
BEGIN
    SELECT
        u.UserId,
        u.Username,
        u.PasswordHash,
        u.RoleId,
        r.RoleName,
        u.employee_id,
        u.IsActive,
        u.CreatedAt,
        u.CanViewImportPrice,
        u.CanEditImportPrice,
        u.CanEditSellPrice,
        u.CanEditStock,
        u.CanDeleteInvoice,
        u.CanEditProductInfo,
        u.CanImportProductExcel,
        u.CanStocktake,
        u.CanEditSalesInvoice,
        u.CanCancelSalesInvoice,
        u.CanEditPurchaseInvoice,
        u.CanCancelPurchaseInvoice,
        u.CanDeletePurchaseInvoice,
        u.CanDeletePaymentVoucher,
        u.CanManageCustomers,
        u.CanManageSuppliers,
        u.CanManageCatalogs
    FROM dbo.Users u
    INNER JOIN dbo.Roles r ON u.RoleId = r.RoleId
    WHERE u.Username = @Username;
END
GO

IF OBJECT_ID(N'dbo.Users_Insert', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Users_Insert;
GO

CREATE PROCEDURE dbo.Users_Insert
    @Username NVARCHAR(50),
    @PasswordHash NVARCHAR(255),
    @RoleId INT,
    @EmployeeId INT = NULL,
    @CanViewImportPrice BIT = 0,
    @CanEditImportPrice BIT = 0,
    @CanEditSellPrice BIT = 0,
    @CanEditStock BIT = 0,
    @CanDeleteInvoice BIT = 0,
    @CanEditProductInfo BIT = 0,
    @CanImportProductExcel BIT = 0,
    @CanStocktake BIT = 0,
    @CanEditSalesInvoice BIT = 0,
    @CanCancelSalesInvoice BIT = 0,
    @CanEditPurchaseInvoice BIT = 0,
    @CanCancelPurchaseInvoice BIT = 0,
    @CanDeletePurchaseInvoice BIT = 0,
    @CanDeletePaymentVoucher BIT = 0,
    @CanManageCustomers BIT = 0,
    @CanManageSuppliers BIT = 0,
    @CanManageCatalogs BIT = 0
AS
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username = @Username)
        RETURN 0;

    IF @EmployeeId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Users WHERE employee_id = @EmployeeId)
        RETURN 0;

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
        @RoleId,
        @EmployeeId,
        1,
        GETDATE(),
        @CanViewImportPrice,
        @CanEditImportPrice,
        @CanEditSellPrice,
        @CanEditStock,
        @CanDeleteInvoice,
        @CanEditProductInfo,
        @CanImportProductExcel,
        @CanStocktake,
        @CanEditSalesInvoice,
        @CanCancelSalesInvoice,
        @CanEditPurchaseInvoice,
        @CanCancelPurchaseInvoice,
        @CanDeletePurchaseInvoice,
        @CanDeletePaymentVoucher,
        @CanManageCustomers,
        @CanManageSuppliers,
        @CanManageCatalogs
    );
END
GO

IF OBJECT_ID(N'dbo.Users_Update', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Users_Update;
GO

CREATE PROCEDURE dbo.Users_Update
    @UserId INT,
    @RoleId INT,
    @IsActive BIT,
    @CanViewImportPrice BIT = 0,
    @CanEditImportPrice BIT = 0,
    @CanEditSellPrice BIT = 0,
    @CanEditStock BIT = 0,
    @CanDeleteInvoice BIT = 0,
    @CanEditProductInfo BIT = 0,
    @CanImportProductExcel BIT = 0,
    @CanStocktake BIT = 0,
    @CanEditSalesInvoice BIT = 0,
    @CanCancelSalesInvoice BIT = 0,
    @CanEditPurchaseInvoice BIT = 0,
    @CanCancelPurchaseInvoice BIT = 0,
    @CanDeletePurchaseInvoice BIT = 0,
    @CanDeletePaymentVoucher BIT = 0,
    @CanManageCustomers BIT = 0,
    @CanManageSuppliers BIT = 0,
    @CanManageCatalogs BIT = 0
AS
BEGIN
    UPDATE dbo.Users
    SET
        RoleId = @RoleId,
        IsActive = @IsActive,
        CanViewImportPrice = @CanViewImportPrice,
        CanEditImportPrice = @CanEditImportPrice,
        CanEditSellPrice = @CanEditSellPrice,
        CanEditStock = @CanEditStock,
        CanDeleteInvoice = @CanDeleteInvoice,
        CanEditProductInfo = @CanEditProductInfo,
        CanImportProductExcel = @CanImportProductExcel,
        CanStocktake = @CanStocktake,
        CanEditSalesInvoice = @CanEditSalesInvoice,
        CanCancelSalesInvoice = @CanCancelSalesInvoice,
        CanEditPurchaseInvoice = @CanEditPurchaseInvoice,
        CanCancelPurchaseInvoice = @CanCancelPurchaseInvoice,
        CanDeletePurchaseInvoice = @CanDeletePurchaseInvoice,
        CanDeletePaymentVoucher = @CanDeletePaymentVoucher,
        CanManageCustomers = @CanManageCustomers,
        CanManageSuppliers = @CanManageSuppliers,
        CanManageCatalogs = @CanManageCatalogs
    WHERE UserId = @UserId;
END
GO
