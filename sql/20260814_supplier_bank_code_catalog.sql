/* Feature 2026-08-14
   Store the VietQR bank code separately from the display name.
   Safe to run more than once on an existing database.
*/

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.suppliers', N'U') IS NULL
    THROW 50001, N'Không tìm thấy bảng dbo.suppliers.', 1;

IF COL_LENGTH(N'dbo.suppliers', N'bank_code') IS NULL
    ALTER TABLE dbo.suppliers ADD bank_code NVARCHAR(30) NULL;
GO

/* Preserve old free-text bank data by converting the common names to VietQR codes. */
EXEC(N'
UPDATE dbo.suppliers
SET bank_code = CASE
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''ICB'', N''VTB'', N''VIETINBANK'') THEN N''ICB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''VCB'', N''VIETCOMBANK'') THEN N''VCB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''BIDV'' THEN N''BIDV''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''VBA'', N''AGRIBANK'') THEN N''VBA''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''MB'', N''MBBANK'') THEN N''MB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''TCB'', N''TECHCOMBANK'') THEN N''TCB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''ACB'' THEN N''ACB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''VPB'', N''VPBANK'') THEN N''VPB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''TPB'', N''TPBANK'') THEN N''TPB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''STB'', N''SACOMBANK'') THEN N''STB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''HDB'', N''HDBANK'') THEN N''HDB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''OCB'' THEN N''OCB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''VIB'' THEN N''VIB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''SHB'' THEN N''SHB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''EIB'', N''EXIMBANK'') THEN N''EIB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) = N''MSB'' THEN N''MSB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''BAB'', N''BACABANK'') THEN N''BAB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''ABB'', N''ABBANK'') THEN N''ABB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''VAB'', N''VIETABANK'') THEN N''VAB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''NAB'', N''NAMABANK'') THEN N''NAB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''PGB'', N''PGBANK'') THEN N''PGB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''SEAB'', N''SEABANK'') THEN N''SEAB''
    WHEN UPPER(LTRIM(RTRIM(ISNULL(bank_name, N'''')))) IN (N''LPB'', N''LPBANK'', N''LIENVIETPOSTBANK'') THEN N''LPB''
    ELSE bank_code
END
WHERE NULLIF(LTRIM(RTRIM(ISNULL(bank_code, N''''))), N'''') IS NULL;
');
GO

IF OBJECT_ID(N'dbo.Suppliers_GetAll', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_GetAll AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT supplier_id AS SupplierId, supplier_name AS SupplierName, phone AS Phone,
           address AS Address, email AS Email, tax_code AS TaxCode,
           ISNULL(bank_code, N'') AS BankCode, bank_name AS BankName,
           bank_account AS BankAccount, bank_owner AS BankOwner, is_active AS IsActive
    FROM dbo.suppliers
    ORDER BY supplier_name;
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_Search', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_Search @Keyword NVARCHAR(100) AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_Search
    @Keyword NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT supplier_id AS SupplierId, supplier_name AS SupplierName, phone AS Phone,
           address AS Address, email AS Email, tax_code AS TaxCode,
           ISNULL(bank_code, N'') AS BankCode, bank_name AS BankName,
           bank_account AS BankAccount, bank_owner AS BankOwner, is_active AS IsActive
    FROM dbo.suppliers
    WHERE is_active = 1
      AND (supplier_name LIKE N'%' + @Keyword + N'%'
           OR phone LIKE N'%' + @Keyword + N'%'
           OR bank_code LIKE N'%' + @Keyword + N'%'
           OR bank_name LIKE N'%' + @Keyword + N'%'
           OR bank_account LIKE N'%' + @Keyword + N'%'
           OR bank_owner LIKE N'%' + @Keyword + N'%')
    ORDER BY supplier_name;
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_GetById', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_GetById @SupplierId INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_GetById
    @SupplierId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT supplier_id AS SupplierId, supplier_name AS SupplierName, phone AS Phone,
           address AS Address, email AS Email, tax_code AS TaxCode,
           ISNULL(bank_code, N'') AS BankCode, bank_name AS BankName,
           bank_account AS BankAccount, bank_owner AS BankOwner, is_active AS IsActive
    FROM dbo.suppliers
    WHERE supplier_id = @SupplierId;
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_Insert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_Insert @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255), @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankCode NVARCHAR(30), @BankName NVARCHAR(100), @BankAccount NVARCHAR(50), @BankOwner NVARCHAR(150), @IsActive BIT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_Insert
    @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255),
    @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankCode NVARCHAR(30),
    @BankName NVARCHAR(100), @BankAccount NVARCHAR(50),
    @BankOwner NVARCHAR(150), @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.suppliers
        (supplier_name, phone, address, email, tax_code, bank_code, bank_name, bank_account, bank_owner, is_active)
    VALUES
        (@Name, @Phone, @Address, @Email, @TaxCode, @BankCode, @BankName, @BankAccount, @BankOwner, @IsActive);
    SELECT SCOPE_IDENTITY();
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_Update', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_Update @Id INT, @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255), @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankCode NVARCHAR(30), @BankName NVARCHAR(100), @BankAccount NVARCHAR(50), @BankOwner NVARCHAR(150), @IsActive BIT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_Update
    @Id INT, @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255),
    @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankCode NVARCHAR(30),
    @BankName NVARCHAR(100), @BankAccount NVARCHAR(50),
    @BankOwner NVARCHAR(150), @IsActive BIT
AS
BEGIN
    SET NOCOUNT OFF;
    UPDATE dbo.suppliers
    SET supplier_name = @Name, phone = @Phone, address = @Address,
        email = @Email, tax_code = @TaxCode, bank_code = @BankCode,
        bank_name = @BankName, bank_account = @BankAccount,
        bank_owner = @BankOwner, is_active = @IsActive
    WHERE supplier_id = @Id;
END;
GO

