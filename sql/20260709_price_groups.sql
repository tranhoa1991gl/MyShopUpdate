IF COL_LENGTH(N'dbo.products', N'price_1') IS NULL
    ALTER TABLE dbo.products ADD price_1 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_1 DEFAULT (0);

IF COL_LENGTH(N'dbo.products', N'price_2') IS NULL
    ALTER TABLE dbo.products ADD price_2 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_2 DEFAULT (0);

IF COL_LENGTH(N'dbo.products', N'price_3') IS NULL
    ALTER TABLE dbo.products ADD price_3 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_3 DEFAULT (0);

IF COL_LENGTH(N'dbo.products', N'price_4') IS NULL
    ALTER TABLE dbo.products ADD price_4 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_4 DEFAULT (0);

IF COL_LENGTH(N'dbo.customers', N'price_group_level') IS NULL
    ALTER TABLE dbo.customers ADD price_group_level INT NOT NULL CONSTRAINT DF_customers_price_group_level DEFAULT (0);
