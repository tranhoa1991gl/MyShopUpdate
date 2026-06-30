IF COL_LENGTH(N'dbo.Users', N'CanViewImportPrice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanViewImportPrice BIT NOT NULL CONSTRAINT DF_Users_CanViewImportPrice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanEditImportPrice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditImportPrice BIT NOT NULL CONSTRAINT DF_Users_CanEditImportPrice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanEditSellPrice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditSellPrice BIT NOT NULL CONSTRAINT DF_Users_CanEditSellPrice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanEditStock') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditStock BIT NOT NULL CONSTRAINT DF_Users_CanEditStock DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanDeleteInvoice') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanDeleteInvoice BIT NOT NULL CONSTRAINT DF_Users_CanDeleteInvoice DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanEditProductInfo') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanEditProductInfo BIT NOT NULL CONSTRAINT DF_Users_CanEditProductInfo DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanImportProductExcel') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanImportProductExcel BIT NOT NULL CONSTRAINT DF_Users_CanImportProductExcel DEFAULT (0);
END
GO

IF COL_LENGTH(N'dbo.Users', N'CanStocktake') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD CanStocktake BIT NOT NULL CONSTRAINT DF_Users_CanStocktake DEFAULT (0);
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
    CanStocktake = 1
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
        u.CanStocktake
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
    @CanStocktake BIT = 0
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
        CanStocktake
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
        @CanStocktake
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
    @CanStocktake BIT = 0
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
        CanStocktake = @CanStocktake
    WHERE UserId = @UserId;
END
GO
