IF COL_LENGTH(N'dbo.customers', N'customer_code') IS NULL
    ALTER TABLE dbo.customers ADD customer_code NVARCHAR(50) NULL;
GO

UPDATE dbo.customers
SET customer_code = N'KH' + RIGHT(N'000000' + CAST(customer_id AS NVARCHAR(20)), 6)
WHERE NULLIF(LTRIM(RTRIM(ISNULL(customer_code, N''))), N'') IS NULL;
GO

;WITH duplicated AS
(
    SELECT
        customer_id,
        ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(customer_code)) ORDER BY customer_id) AS row_no
    FROM dbo.customers
    WHERE NULLIF(LTRIM(RTRIM(ISNULL(customer_code, N''))), N'') IS NOT NULL
)
UPDATE c
SET customer_code = N'KH' + RIGHT(N'000000' + CAST(c.customer_id AS NVARCHAR(20)), 6) + N'-' + CAST(d.row_no AS NVARCHAR(10))
FROM dbo.customers c
INNER JOIN duplicated d ON c.customer_id = d.customer_id
WHERE d.row_no > 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UX_customers_customer_code'
      AND object_id = OBJECT_ID(N'dbo.customers')
)
    CREATE UNIQUE INDEX UX_customers_customer_code
    ON dbo.customers(customer_code)
    WHERE customer_code IS NOT NULL AND customer_code <> N'';
GO

IF COL_LENGTH(N'dbo.products', N'product_location') IS NULL
    ALTER TABLE dbo.products ADD product_location NVARCHAR(100) NULL;
GO

IF COL_LENGTH(N'dbo.customer_payments', N'payment_method') IS NULL
    ALTER TABLE dbo.customer_payments ADD payment_method NVARCHAR(50) NULL;
GO

UPDATE dbo.customer_payments
SET payment_method = N'Tiền mặt'
WHERE NULLIF(LTRIM(RTRIM(ISNULL(payment_method, N''))), N'') IS NULL;
GO

ALTER PROCEDURE [dbo].[CustomerPayments_Insert]
    @CustomerId INT,
    @Amount DECIMAL(18,0),
    @EmployeeId INT = 0,
    @Note NVARCHAR(MAX) = NULL,
    @PaymentMethod NVARCHAR(50) = N'Tiền mặt'
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.customer_payments
        (customer_id, payment_date, amount, employee_id, note, payment_method)
    VALUES
        (@CustomerId, GETDATE(), @Amount, @EmployeeId, @Note, ISNULL(NULLIF(LTRIM(RTRIM(@PaymentMethod)), N''), N'Tiền mặt'));
END
GO

ALTER PROCEDURE [dbo].[CustomerPayments_GetHistory]
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.payment_id AS PaymentId,
        p.customer_id AS CustomerId,
        c.name AS CustomerName,
        p.payment_date AS PaymentDate,
        p.amount AS Amount,
        p.employee_id AS EmployeeId,
        e.name AS EmployeeName,
        ISNULL(p.payment_method, N'Tiền mặt') AS PaymentMethod,
        p.note AS Note
    FROM dbo.customer_payments p
    INNER JOIN dbo.customers c ON p.customer_id = c.customer_id
    LEFT JOIN dbo.employees e ON p.employee_id = e.employee_id
    WHERE p.payment_date >= @FromDate
      AND p.payment_date <= @ToDate
    ORDER BY p.payment_date DESC;
END
GO
