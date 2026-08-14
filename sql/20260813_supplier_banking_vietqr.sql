/* Feature 2026-08-13
   Store one default bank account per supplier and persist the payment method
   used when settling supplier debt. Safe to run on an existing database.
*/

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.suppliers', N'U') IS NULL
    THROW 50001, N'Không tìm thấy bảng dbo.suppliers.', 1;

IF COL_LENGTH(N'dbo.suppliers', N'bank_name') IS NULL
    ALTER TABLE dbo.suppliers ADD bank_name NVARCHAR(100) NULL;

IF COL_LENGTH(N'dbo.suppliers', N'bank_account') IS NULL
    ALTER TABLE dbo.suppliers ADD bank_account NVARCHAR(50) NULL;

IF COL_LENGTH(N'dbo.suppliers', N'bank_owner') IS NULL
    ALTER TABLE dbo.suppliers ADD bank_owner NVARCHAR(150) NULL;

IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.supplier_payments', N'payment_method') IS NULL
BEGIN
    ALTER TABLE dbo.supplier_payments ADD payment_method NVARCHAR(50) NULL;
END;

IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
BEGIN
    EXEC(N'
        UPDATE dbo.supplier_payments
        SET payment_method = N''Tiền mặt''
        WHERE NULLIF(LTRIM(RTRIM(ISNULL(payment_method, N''''))), N'''') IS NULL;
    ');
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_GetAll', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_GetAll AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        supplier_id AS SupplierId,
        supplier_name AS SupplierName,
        phone AS Phone,
        address AS Address,
        email AS Email,
        tax_code AS TaxCode,
        bank_name AS BankName,
        bank_account AS BankAccount,
        bank_owner AS BankOwner,
        is_active AS IsActive
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

    SELECT
        supplier_id AS SupplierId,
        supplier_name AS SupplierName,
        phone AS Phone,
        address AS Address,
        email AS Email,
        tax_code AS TaxCode,
        bank_name AS BankName,
        bank_account AS BankAccount,
        bank_owner AS BankOwner,
        is_active AS IsActive
    FROM dbo.suppliers
    WHERE is_active = 1
      AND
      (
          supplier_name LIKE N'%' + @Keyword + N'%'
          OR phone LIKE N'%' + @Keyword + N'%'
          OR bank_name LIKE N'%' + @Keyword + N'%'
          OR bank_account LIKE N'%' + @Keyword + N'%'
          OR bank_owner LIKE N'%' + @Keyword + N'%'
      )
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

    SELECT
        supplier_id AS SupplierId,
        supplier_name AS SupplierName,
        phone AS Phone,
        address AS Address,
        email AS Email,
        tax_code AS TaxCode,
        bank_name AS BankName,
        bank_account AS BankAccount,
        bank_owner AS BankOwner,
        is_active AS IsActive
    FROM dbo.suppliers
    WHERE supplier_id = @SupplierId;
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_Insert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_Insert @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255), @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankName NVARCHAR(100), @BankAccount NVARCHAR(50), @BankOwner NVARCHAR(150), @IsActive BIT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_Insert
    @Name NVARCHAR(100),
    @Phone VARCHAR(20),
    @Address NVARCHAR(255),
    @Email VARCHAR(100),
    @TaxCode VARCHAR(50),
    @BankName NVARCHAR(100),
    @BankAccount NVARCHAR(50),
    @BankOwner NVARCHAR(150),
    @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.suppliers
        (supplier_name, phone, address, email, tax_code, bank_name, bank_account, bank_owner, is_active)
    VALUES
        (@Name, @Phone, @Address, @Email, @TaxCode, @BankName, @BankAccount, @BankOwner, @IsActive);

    SELECT SCOPE_IDENTITY();
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_Update', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_Update @Id INT, @Name NVARCHAR(100), @Phone VARCHAR(20), @Address NVARCHAR(255), @Email VARCHAR(100), @TaxCode VARCHAR(50), @BankName NVARCHAR(100), @BankAccount NVARCHAR(50), @BankOwner NVARCHAR(150), @IsActive BIT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_Update
    @Id INT,
    @Name NVARCHAR(100),
    @Phone VARCHAR(20),
    @Address NVARCHAR(255),
    @Email VARCHAR(100),
    @TaxCode VARCHAR(50),
    @BankName NVARCHAR(100),
    @BankAccount NVARCHAR(50),
    @BankOwner NVARCHAR(150),
    @IsActive BIT
AS
BEGIN
    -- Supplier.Update relies on ExecuteNonQuery() returning the affected-row count.
    SET NOCOUNT OFF;

    UPDATE dbo.suppliers
    SET supplier_name = @Name,
        phone = @Phone,
        address = @Address,
        email = @Email,
        tax_code = @TaxCode,
        bank_name = @BankName,
        bank_account = @BankAccount,
        bank_owner = @BankOwner,
        is_active = @IsActive
    WHERE supplier_id = @Id;
END;
GO

IF OBJECT_ID(N'dbo.Suppliers_GetWithDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Suppliers_GetWithDebt AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Suppliers_GetWithDebt
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM
    (
        SELECT
            s.supplier_id AS SupplierId,
            ISNULL(s.supplier_name, N'') AS SupplierName,
            ISNULL(s.phone, N'') AS Phone,
            ISNULL(s.address, N'') AS Address,
            ISNULL(s.email, N'') AS Email,
            ISNULL(s.tax_code, N'') AS TaxCode,
            ISNULL(s.bank_name, N'') AS BankName,
            ISNULL(s.bank_account, N'') AS BankAccount,
            ISNULL(s.bank_owner, N'') AS BankOwner,
            ISNULL(s.is_active, 1) AS IsActive,
            CASE
                WHEN ISNULL(d.ImportDebt, 0) - ISNULL(p.TotalPaid, 0) > 0
                    THEN ISNULL(d.ImportDebt, 0) - ISNULL(p.TotalPaid, 0)
                ELSE 0
            END AS CurrentDebt
        FROM dbo.suppliers s
        OUTER APPLY
        (
            SELECT SUM
            (
                CASE
                    WHEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                        THEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                    ELSE 0
                END
            ) AS ImportDebt
            FROM dbo.imports i
            OUTER APPLY
            (
                SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
                FROM dbo.purchase_returns pr
                WHERE pr.import_id = i.import_id
                  AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
            ) r
            WHERE i.supplier_id = s.supplier_id
              AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) d
        OUTER APPLY
        (
            SELECT SUM(ISNULL(amount, 0)) AS TotalPaid
            FROM dbo.supplier_payments
            WHERE supplier_id = s.supplier_id
        ) p
    ) X
    WHERE X.CurrentDebt > 0
    ORDER BY X.SupplierName;
END;
GO

IF OBJECT_ID(N'dbo.SupplierPayments_GetHistory', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.SupplierPayments_GetHistory @FromDate DATETIME, @ToDate DATETIME AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.SupplierPayments_GetHistory
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.payment_id AS PaymentId,
        p.supplier_id AS SupplierId,
        s.supplier_name AS SupplierName,
        p.payment_date AS PaymentDate,
        p.amount AS Amount,
        ISNULL(p.payment_method, N'Tiền mặt') AS PaymentMethod,
        p.note AS Note,
        p.employee_id AS EmployeeId,
        e.Name AS EmployeeName
    FROM dbo.supplier_payments p
    LEFT JOIN dbo.suppliers s ON p.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON p.employee_id = e.employee_id
    WHERE p.payment_date BETWEEN @FromDate AND @ToDate
    ORDER BY p.payment_date DESC;
END;
GO

IF OBJECT_ID(N'dbo.SupplierPayments_GetList', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.SupplierPayments_GetList @supplier_id INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.SupplierPayments_GetList
    @supplier_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.payment_id AS PaymentId,
        p.supplier_id AS SupplierId,
        s.supplier_name AS SupplierName,
        p.payment_date AS PaymentDate,
        p.amount AS Amount,
        ISNULL(p.payment_method, N'Tiền mặt') AS PaymentMethod,
        p.employee_id AS EmployeeId,
        e.name AS EmployeeName,
        p.note AS Note
    FROM dbo.supplier_payments p
    LEFT JOIN dbo.suppliers s ON p.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON p.employee_id = e.employee_id
    WHERE p.supplier_id = @supplier_id
    ORDER BY p.payment_date DESC;
END;
GO
