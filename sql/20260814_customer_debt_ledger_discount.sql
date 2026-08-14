SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.customer_debt_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customer_debt_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_customer_debt_adjustments PRIMARY KEY,
        customer_id INT NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_customer_debt_adjustments_date DEFAULT (GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        adjustment_type NVARCHAR(30) NOT NULL CONSTRAINT DF_customer_debt_adjustments_type DEFAULT (N'DISCOUNT'),
        employee_id INT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_customer_debt_adjustments_created DEFAULT (GETDATE()),
        CONSTRAINT CK_customer_debt_adjustments_amount CHECK (amount > 0)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.customer_debt_adjustments')
      AND name = N'IX_customer_debt_adjustments_customer_date'
)
    CREATE INDEX IX_customer_debt_adjustments_customer_date
    ON dbo.customer_debt_adjustments(customer_id, adjustment_date, adjustment_id);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_customer_debt_adjustments_amount'
      AND parent_object_id = OBJECT_ID(N'dbo.customer_debt_adjustments')
)
    ALTER TABLE dbo.customer_debt_adjustments WITH CHECK
    ADD CONSTRAINT CK_customer_debt_adjustments_amount CHECK (amount > 0);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_customer_debt_adjustments_customers'
)
    ALTER TABLE dbo.customer_debt_adjustments WITH CHECK
    ADD CONSTRAINT FK_customer_debt_adjustments_customers
    FOREIGN KEY(customer_id) REFERENCES dbo.customers(customer_id);
GO

IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1 FROM sys.foreign_keys
       WHERE name = N'FK_customer_debt_adjustments_employees'
   )
    ALTER TABLE dbo.customer_debt_adjustments WITH CHECK
    ADD CONSTRAINT FK_customer_debt_adjustments_employees
    FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);
GO

IF OBJECT_ID(N'dbo.Customer_GetCurrentDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Customer_GetCurrentDebt @CustomerId INT AS SELECT 0 AS CurrentDebt;');
GO

ALTER PROCEDURE dbo.Customer_GetCurrentDebt
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
        FROM dbo.orders
        WHERE customer_id = @CustomerId
          AND ISNULL(status, N'') <> N'Cancelled'
    ), 0);

    DECLARE @PaidDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.customer_payments
        WHERE customer_id = @CustomerId
    ), 0);

    DECLARE @AdjustedDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.customer_debt_adjustments
        WHERE customer_id = @CustomerId
    ), 0);

    SELECT CASE WHEN @OrderDebt - @PaidDebt - @AdjustedDebt > 0
        THEN @OrderDebt - @PaidDebt - @AdjustedDebt ELSE 0 END AS CurrentDebt;
END;
GO

IF OBJECT_ID(N'dbo.CustomerPayments_GetDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.CustomerPayments_GetDebt @CustomerId INT AS SELECT 0 AS CurrentDebt;');
GO

ALTER PROCEDURE dbo.CustomerPayments_GetDebt
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
        FROM dbo.orders
        WHERE customer_id = @CustomerId
          AND ISNULL(status, N'') <> N'Cancelled'
    ), 0);

    DECLARE @PaidDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.customer_payments
        WHERE customer_id = @CustomerId
    ), 0);

    DECLARE @AdjustedDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.customer_debt_adjustments
        WHERE customer_id = @CustomerId
    ), 0);

    SELECT CASE WHEN @OrderDebt - @PaidDebt - @AdjustedDebt > 0
        THEN @OrderDebt - @PaidDebt - @AdjustedDebt ELSE 0 END AS CurrentDebt;
END;
GO

IF OBJECT_ID(N'dbo.Customers_GetListWithDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Customers_GetListWithDebt AS SELECT 1 AS EmptyResult WHERE 1 = 0;');
GO

ALTER PROCEDURE dbo.Customers_GetListWithDebt
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.customer_id AS CustomerId,
        ISNULL(c.customer_code, N'') AS CustomerCode,
        ISNULL(c.name, N'') AS CustomerName,
        ISNULL(c.phone, N'') AS Phone,
        ISNULL(c.address, N'') AS Address,
        ISNULL(c.email, N'') AS Email,
        x.CurrentDebt
    FROM dbo.customers c
    OUTER APPLY
    (
        SELECT
            ISNULL((
                SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
                FROM dbo.orders
                WHERE customer_id = c.customer_id
                  AND ISNULL(status, N'') <> N'Cancelled'
            ), 0)
            - ISNULL((
                SELECT SUM(ISNULL(amount, 0))
                FROM dbo.customer_payments
                WHERE customer_id = c.customer_id
            ), 0)
            - ISNULL((
                SELECT SUM(ISNULL(amount, 0))
                FROM dbo.customer_debt_adjustments
                WHERE customer_id = c.customer_id
            ), 0) AS CurrentDebt
    ) x
    WHERE x.CurrentDebt > 0
    ORDER BY x.CurrentDebt DESC, c.name ASC;
END;
GO
