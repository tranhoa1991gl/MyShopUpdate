SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @LockResult INT;
EXEC @LockResult = sys.sp_getapplock @Resource=N'HoaTranPOS.PurchaseShippingFee',
    @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
IF @LockResult < 0
    THROW 51000, N'Không thể khóa cập nhật cấu trúc phí vận chuyển.', 1;

IF COL_LENGTH(N'dbo.imports', N'shipping_fee') IS NULL
    ALTER TABLE dbo.imports ADD shipping_fee DECIMAL(18,0) NOT NULL
        CONSTRAINT DF_imports_shipping_fee DEFAULT (0);

IF COL_LENGTH(N'dbo.imports', N'shipping_paid_to_supplier') IS NULL
    ALTER TABLE dbo.imports ADD shipping_paid_to_supplier BIT NOT NULL
        CONSTRAINT DF_imports_shipping_paid_to_supplier DEFAULT (1);

IF COL_LENGTH(N'dbo.imports', N'shipping_payment_method') IS NULL
    ALTER TABLE dbo.imports ADD shipping_payment_method NVARCHAR(50) NOT NULL
        CONSTRAINT DF_imports_shipping_payment_method DEFAULT (N'Tiền mặt');

IF COL_LENGTH(N'dbo.import_details', N'allocated_shipping_fee') IS NULL
    ALTER TABLE dbo.import_details ADD allocated_shipping_fee DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_import_details_allocated_shipping_fee DEFAULT (0);

IF COL_LENGTH(N'dbo.import_details', N'stock_import_price') IS NULL
    ALTER TABLE dbo.import_details ADD stock_import_price DECIMAL(18,2) NULL;
GO
CREATE OR ALTER PROCEDURE [dbo].[Imports_GetById]
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
        i.shipping_fee AS ShippingFee,
        i.shipping_paid_to_supplier AS ShippingPaidToSupplier,
        i.shipping_payment_method AS ShippingPaymentMethod,
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
CREATE OR ALTER PROCEDURE [dbo].[Imports_GetList]
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
        i.shipping_fee AS ShippingFee,
        i.shipping_paid_to_supplier AS ShippingPaidToSupplier,
        i.shipping_payment_method AS ShippingPaymentMethod,
        i.final_amount AS FinalAmount,
        i.paid_amount AS PaidAmount,
        ISNULL(i.payment_method, N'Tiền mặt') AS PaymentMethod,
        i.status AS Status,
        i.note AS Note
    FROM dbo.imports i
    LEFT JOIN dbo.suppliers s ON i.supplier_id = s.supplier_id
    LEFT JOIN dbo.employees e ON i.employee_id = e.employee_id
    WHERE i.import_date >= @FromDate AND i.import_date < DATEADD(DAY, 1, CAST(@ToDate AS DATE))
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
CREATE OR ALTER PROCEDURE [dbo].[Imports_Insert]
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
    @Status VARCHAR(50),
    @ShippingFee DECIMAL(18,0) = 0,
    @ShippingPaidToSupplier BIT = 1,
    @ShippingPaymentMethod NVARCHAR(50) = N'Tiền mặt'
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
        shipping_fee,
        shipping_paid_to_supplier,
        shipping_payment_method,
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
        @ShippingFee,
        @ShippingPaidToSupplier,
        @ShippingPaymentMethod,
        @FinalAmount,
        @PaidAmount,
        COALESCE(NULLIF(LTRIM(RTRIM(@PaymentMethod)), N''), N'Tiền mặt'),
        @Note,
        @Status
    );

    SELECT SCOPE_IDENTITY();
END;
GO
CREATE OR ALTER PROCEDURE [dbo].[Imports_UpdateInfo]
    @import_id int,
    @supplier_id int,
    @total_amount decimal(18,0),
    @discount decimal(18,0),
    @vat_amount decimal(18,0),  -- [MỚI] Thêm VAT để không bị mất dữ liệu thuế
    @final_amount decimal(18,0),
    @paid_amount decimal(18,0), -- [MỚI] Thêm số tiền Đã thanh toán
    @note nvarchar(max),
    @shipping_fee decimal(18,0) = NULL,
    @shipping_paid_to_supplier bit = NULL,
    @shipping_payment_method nvarchar(50) = NULL
AS
BEGIN
    UPDATE dbo.imports
    SET 
        supplier_id = @supplier_id,
        total_amount = @total_amount,
        discount = @discount,
        vat_amount = @vat_amount, -- [MỚI]
        shipping_fee = ISNULL(@shipping_fee, shipping_fee),
        shipping_paid_to_supplier = ISNULL(@shipping_paid_to_supplier, shipping_paid_to_supplier),
        shipping_payment_method = ISNULL(@shipping_payment_method, shipping_payment_method),
        final_amount = @final_amount,
        paid_amount = @paid_amount, -- [MỚI]
        note = @note
    WHERE import_id = @import_id
END
GO
COMMIT TRANSACTION;
