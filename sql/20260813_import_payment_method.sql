/* Feature 2026-08-13
   Persist the payment method used when receiving goods from a supplier.
   Safe to run repeatedly on an existing database.
*/

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.imports', N'U') IS NULL
    THROW 50001, N'Không tìm thấy bảng dbo.imports.', 1;

IF COL_LENGTH(N'dbo.imports', N'payment_method') IS NULL
    ALTER TABLE dbo.imports ADD payment_method NVARCHAR(50) NULL;

EXEC(N'
    UPDATE dbo.imports
    SET payment_method = N''Tiền mặt''
    WHERE NULLIF(LTRIM(RTRIM(ISNULL(payment_method, N''''))), N'''') IS NULL;
');
GO

IF OBJECT_ID(N'dbo.Imports_Insert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Imports_Insert AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Imports_Insert
    @ImportCode VARCHAR(50),
    @SupplierId INT,
    @EmployeeId INT,
    @TotalAmount DECIMAL(18,0),
    @Discount DECIMAL(18,0),
    @VatAmount DECIMAL(18,0),
    @FinalAmount DECIMAL(18,0),
    @PaidAmount DECIMAL(18,0),
    @PaymentMethod NVARCHAR(50),
    @Note NVARCHAR(MAX),
    @Status VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.imports
    (
        import_code,
        supplier_id,
        employee_id,
        import_date,
        total_amount,
        discount,
        vat_amount,
        final_amount,
        paid_amount,
        payment_method,
        note,
        status
    )
    VALUES
    (
        @ImportCode,
        @SupplierId,
        @EmployeeId,
        GETDATE(),
        @TotalAmount,
        @Discount,
        @VatAmount,
        @FinalAmount,
        @PaidAmount,
        COALESCE(NULLIF(LTRIM(RTRIM(@PaymentMethod)), N''), N'Tiền mặt'),
        @Note,
        @Status
    );

    SELECT SCOPE_IDENTITY();
END;
GO

IF OBJECT_ID(N'dbo.Imports_GetById', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Imports_GetById @ImportId INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Imports_GetById
    @ImportId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.import_id AS ImportId,
        i.import_code AS ImportCode,
        i.supplier_id AS SupplierId,
        i.employee_id AS EmployeeId,
        i.import_date AS ImportDate,
        i.total_amount AS TotalAmount,
        i.vat_amount AS VatAmount,
        i.discount AS Discount,
        i.final_amount AS FinalAmount,
        i.paid_amount AS PaidAmount,
        ISNULL(i.payment_method, N'Tiền mặt') AS PaymentMethod,
        i.note AS Note,
        i.status AS Status,
        s.supplier_name AS SupplierName,
        s.phone AS SupplierPhone,
        s.address AS SupplierAddress,
        e.name AS EmployeeName
    FROM dbo.imports i
    LEFT JOIN dbo.suppliers s ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON i.employee_id = e.employee_id
    WHERE i.import_id = @ImportId;
END;
GO

IF OBJECT_ID(N'dbo.Imports_GetList', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Imports_GetList @FromDate DATETIME, @ToDate DATETIME, @Keyword NVARCHAR(100), @Status NVARCHAR(50) AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Imports_GetList
    @FromDate DATETIME,
    @ToDate DATETIME,
    @Keyword NVARCHAR(100),
    @Status NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.import_id AS ImportId,
        i.import_code AS ImportCode,
        i.supplier_id AS SupplierId,
        i.employee_id AS EmployeeId,
        s.supplier_name AS SupplierName,
        i.import_date AS ImportDate,
        e.name AS EmployeeName,
        i.total_amount AS TotalAmount,
        i.discount AS Discount,
        i.vat_amount AS VatAmount,
        i.final_amount AS FinalAmount,
        i.paid_amount AS PaidAmount,
        ISNULL(i.payment_method, N'Tiền mặt') AS PaymentMethod,
        i.status AS Status,
        i.note AS Note
    FROM dbo.imports i
    LEFT JOIN dbo.suppliers s ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON i.employee_id = e.employee_id
    WHERE i.import_date BETWEEN @FromDate AND @ToDate
      AND
      (
          @Keyword IS NULL OR @Keyword = N''
          OR i.import_code LIKE N'%' + @Keyword + N'%'
          OR s.supplier_name LIKE N'%' + @Keyword + N'%'
          OR e.name LIKE N'%' + @Keyword + N'%'
          OR i.note LIKE N'%' + @Keyword + N'%'
      )
      AND (@Status IS NULL OR @Status = N'' OR @Status = N'All' OR i.status = @Status)
    ORDER BY i.import_date DESC;
END;
GO

IF OBJECT_ID(N'dbo.Imports_GetBySupplier', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Imports_GetBySupplier @SupplierId INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Imports_GetBySupplier
    @SupplierId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.import_id AS ImportId,
        i.import_code AS ImportCode,
        i.supplier_id AS SupplierId,
        i.employee_id AS EmployeeId,
        i.import_date AS ImportDate,
        i.total_amount AS TotalAmount,
        i.vat_amount AS VatAmount,
        i.discount AS Discount,
        i.final_amount AS FinalAmount,
        i.paid_amount AS PaidAmount,
        ISNULL(i.payment_method, N'Tiền mặt') AS PaymentMethod,
        ISNULL
        ((
            SELECT SUM(pr.total_amount)
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS ReturnedAmount,
        i.note AS Note,
        i.status AS Status,
        s.supplier_name AS SupplierName,
        e.name AS EmployeeName
    FROM dbo.imports i
    LEFT JOIN dbo.suppliers s ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON i.employee_id = e.employee_id
    WHERE i.supplier_id = @SupplierId
    ORDER BY i.import_date DESC;
END;
GO
