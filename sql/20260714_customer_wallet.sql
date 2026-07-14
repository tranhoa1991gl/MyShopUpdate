IF COL_LENGTH(N'dbo.customers', N'wallet_balance') IS NULL
    ALTER TABLE dbo.customers ADD wallet_balance DECIMAL(18,2) NOT NULL CONSTRAINT DF_customers_wallet_balance DEFAULT (0);
GO

IF OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customer_wallet_transactions
    (
        wallet_transaction_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_customer_wallet_transactions PRIMARY KEY,
        customer_id INT NOT NULL,
        transaction_date DATETIME NOT NULL CONSTRAINT DF_customer_wallet_transactions_date DEFAULT (GETDATE()),
        transaction_type NVARCHAR(30) NOT NULL,
        amount DECIMAL(18,2) NOT NULL,
        balance_before DECIMAL(18,2) NOT NULL,
        balance_after DECIMAL(18,2) NOT NULL,
        order_id INT NULL,
        note NVARCHAR(500) NULL,
        created_by NVARCHAR(100) NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'balance_before') IS NULL
        ALTER TABLE dbo.customer_wallet_transactions ADD balance_before DECIMAL(18,2) NOT NULL CONSTRAINT DF_customer_wallet_transactions_before DEFAULT (0);

    IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'balance_after') IS NULL
        ALTER TABLE dbo.customer_wallet_transactions ADD balance_after DECIMAL(18,2) NOT NULL CONSTRAINT DF_customer_wallet_transactions_after DEFAULT (0);

    IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'order_id') IS NULL
        ALTER TABLE dbo.customer_wallet_transactions ADD order_id INT NULL;

    IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'created_by') IS NULL
        ALTER TABLE dbo.customer_wallet_transactions ADD created_by NVARCHAR(100) NULL;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_customer_wallet_transactions_customer_date'
      AND object_id = OBJECT_ID(N'dbo.customer_wallet_transactions')
)
    CREATE INDEX IX_customer_wallet_transactions_customer_date
    ON dbo.customer_wallet_transactions(customer_id, transaction_date DESC);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = N'FK_customer_wallet_transactions_customers'
)
    ALTER TABLE dbo.customer_wallet_transactions
    ADD CONSTRAINT FK_customer_wallet_transactions_customers
    FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id);
GO

IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM sys.foreign_keys
        WHERE name = N'FK_customer_wallet_transactions_orders'
   )
    ALTER TABLE dbo.customer_wallet_transactions
    ADD CONSTRAINT FK_customer_wallet_transactions_orders
    FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id);
GO

IF COL_LENGTH(N'dbo.Users', N'CanViewAllWallet') IS NULL
    ALTER TABLE dbo.Users ADD CanViewAllWallet BIT NOT NULL DEFAULT (0);

IF COL_LENGTH(N'dbo.Users', N'CanTopUpWallet') IS NULL
    ALTER TABLE dbo.Users ADD CanTopUpWallet BIT NOT NULL DEFAULT (0);

IF COL_LENGTH(N'dbo.Users', N'CanEditWallet') IS NULL
    ALTER TABLE dbo.Users ADD CanEditWallet BIT NOT NULL DEFAULT (0);
GO

UPDATE dbo.Users
SET
    CanViewAllWallet = 1,
    CanTopUpWallet = 1,
    CanEditWallet = 1
WHERE RoleId = 1 OR LOWER(ISNULL(Username, N'')) = N'admin';
GO
