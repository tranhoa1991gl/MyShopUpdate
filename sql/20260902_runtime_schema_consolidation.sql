/*
    HoaTran POS - Hop nhat schema con duoc EnsureSchema va luc chay.

    Sau khi migration nay duoc ghi nhan trong dbo.__AppSqlMigrations, cac lop
    DataAccess se bo qua DDL luc thao tac. EnsureSchema cu chi con la lop du
    phong cho may cap nhat offline hoac bo sot migration.

    Script idempotent, khong xoa du lieu nghiep vu va co the chay lai an toan.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.products', N'U') IS NULL
   OR OBJECT_ID(N'dbo.customers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Users', N'U') IS NULL
   OR OBJECT_ID(N'dbo.StoreInfo', N'U') IS NULL
   OR OBJECT_ID(N'dbo.orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.order_items', N'U') IS NULL
   OR OBJECT_ID(N'dbo.imports', N'U') IS NULL
   OR OBJECT_ID(N'dbo.import_details', N'U') IS NULL
BEGIN
    THROW 51250, N'Co so du lieu thieu cac bang nen tang. Hay phuc hoi/cap nhat ban Full_DBMyShop truoc.', 1;
END;

/* Thong tin hang hoa va bang gia. */
IF COL_LENGTH(N'dbo.products', N'product_location') IS NULL
    ALTER TABLE dbo.products ADD product_location NVARCHAR(100) NULL;
IF COL_LENGTH(N'dbo.products', N'note') IS NULL
    ALTER TABLE dbo.products ADD note NVARCHAR(MAX) NULL;
IF COL_LENGTH(N'dbo.products', N'price_1') IS NULL
    ALTER TABLE dbo.products ADD price_1 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_1 DEFAULT (0);
IF COL_LENGTH(N'dbo.products', N'price_2') IS NULL
    ALTER TABLE dbo.products ADD price_2 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_2 DEFAULT (0);
IF COL_LENGTH(N'dbo.products', N'price_3') IS NULL
    ALTER TABLE dbo.products ADD price_3 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_3 DEFAULT (0);
IF COL_LENGTH(N'dbo.products', N'price_4') IS NULL
    ALTER TABLE dbo.products ADD price_4 DECIMAL(18,2) NOT NULL CONSTRAINT DF_products_price_4 DEFAULT (0);

/* Ma, nhom gia va vi khach hang. */
IF COL_LENGTH(N'dbo.customers', N'customer_code') IS NULL
    ALTER TABLE dbo.customers ADD customer_code NVARCHAR(50) NULL;

EXEC sys.sp_executesql N'
UPDATE dbo.customers
SET customer_code = N''KH'' + RIGHT(N''000000'' + CAST(customer_id AS NVARCHAR(20)), 6)
WHERE NULLIF(LTRIM(RTRIM(ISNULL(customer_code, N''''))), N'''') IS NULL;

;WITH duplicated AS
(
    SELECT customer_id,
           ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(customer_code)) ORDER BY customer_id) AS row_no
    FROM dbo.customers
    WHERE NULLIF(LTRIM(RTRIM(ISNULL(customer_code, N''''))), N'''') IS NOT NULL
)
UPDATE c
SET customer_code = N''KH'' + RIGHT(N''000000'' + CAST(c.customer_id AS NVARCHAR(20)), 6)
                    + N''-'' + CAST(d.row_no AS NVARCHAR(10))
FROM dbo.customers c
INNER JOIN duplicated d ON d.customer_id = c.customer_id
WHERE d.row_no > 1;';

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.customers') AND name = N'UX_customers_customer_code'
)
    EXEC sys.sp_executesql N'CREATE UNIQUE INDEX UX_customers_customer_code
        ON dbo.customers(customer_code)
        WHERE customer_code IS NOT NULL AND customer_code <> N'''';';

IF COL_LENGTH(N'dbo.customers', N'price_group_level') IS NULL
    ALTER TABLE dbo.customers ADD price_group_level INT NOT NULL
        CONSTRAINT DF_customers_price_group_level DEFAULT (0);

IF COL_LENGTH(N'dbo.customers', N'wallet_balance') IS NULL
    ALTER TABLE dbo.customers ADD wallet_balance DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_customers_wallet_balance DEFAULT (0);

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

IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'balance_before') IS NULL
    ALTER TABLE dbo.customer_wallet_transactions ADD balance_before DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_customer_wallet_transactions_before DEFAULT (0);
IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'balance_after') IS NULL
    ALTER TABLE dbo.customer_wallet_transactions ADD balance_after DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_customer_wallet_transactions_after DEFAULT (0);
IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'order_id') IS NULL
    ALTER TABLE dbo.customer_wallet_transactions ADD order_id INT NULL;
IF COL_LENGTH(N'dbo.customer_wallet_transactions', N'created_by') IS NULL
    ALTER TABLE dbo.customer_wallet_transactions ADD created_by NVARCHAR(100) NULL;

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.customer_wallet_transactions')
      AND name = N'IX_customer_wallet_transactions_customer_date'
)
    CREATE INDEX IX_customer_wallet_transactions_customer_date
        ON dbo.customer_wallet_transactions(customer_id, transaction_date DESC);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_customer_wallet_transactions_customers')
    ALTER TABLE dbo.customer_wallet_transactions WITH CHECK
        ADD CONSTRAINT FK_customer_wallet_transactions_customers
        FOREIGN KEY(customer_id) REFERENCES dbo.customers(customer_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_customer_wallet_transactions_orders')
    ALTER TABLE dbo.customer_wallet_transactions WITH CHECK
        ADD CONSTRAINT FK_customer_wallet_transactions_orders
        FOREIGN KEY(order_id) REFERENCES dbo.orders(order_id);

/* Thong tin cau hinh cua hang. */
IF COL_LENGTH(N'dbo.StoreInfo', N'logo_path') IS NULL
    ALTER TABLE dbo.StoreInfo ADD logo_path NVARCHAR(500) NULL;
IF COL_LENGTH(N'dbo.StoreInfo', N'allow_negative_stock') IS NULL
    ALTER TABLE dbo.StoreInfo ADD allow_negative_stock BIT NOT NULL
        CONSTRAINT DF_StoreInfo_allow_negative_stock DEFAULT (0) WITH VALUES;
IF COL_LENGTH(N'dbo.StoreInfo', N'remember_last_customer_price') IS NULL
    ALTER TABLE dbo.StoreInfo ADD remember_last_customer_price BIT NOT NULL
        CONSTRAINT DF_StoreInfo_remember_last_customer_price DEFAULT (0) WITH VALUES;
IF COL_LENGTH(N'dbo.StoreInfo', N'show_repair_menu') IS NULL
    ALTER TABLE dbo.StoreInfo ADD show_repair_menu BIT NOT NULL
        CONSTRAINT DF_StoreInfo_show_repair_menu DEFAULT (1) WITH VALUES;

/* Phuong thuc thanh toan phieu thu. */
IF OBJECT_ID(N'dbo.customer_payments', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.customer_payments', N'payment_method') IS NULL
        ALTER TABLE dbo.customer_payments ADD payment_method NVARCHAR(50) NULL;

    EXEC sys.sp_executesql N'
    UPDATE dbo.customer_payments
    SET payment_method = N''Tiền mặt''
    WHERE NULLIF(LTRIM(RTRIM(ISNULL(payment_method, N''''))), N'''') IS NULL;';

    DECLARE @CustomerPaymentIdentity NUMERIC(38,0)=ISNULL(IDENT_CURRENT(N'dbo.customer_payments'),0);
    DECLARE @MaxCustomerPaymentId INT=ISNULL((SELECT MAX(payment_id) FROM dbo.customer_payments),0);
    IF @CustomerPaymentIdentity<@MaxCustomerPaymentId
        DBCC CHECKIDENT ('dbo.customer_payments',RESEED) WITH NO_INFOMSGS;
    ELSE IF @CustomerPaymentIdentity<1
        DBCC CHECKIDENT ('dbo.customer_payments',RESEED,1) WITH NO_INFOMSGS;
END;

IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
BEGIN
    DECLARE @SupplierPaymentIdentity NUMERIC(38,0)=ISNULL(IDENT_CURRENT(N'dbo.supplier_payments'),0);
    DECLARE @MaxSupplierPaymentId INT=ISNULL((SELECT MAX(payment_id) FROM dbo.supplier_payments),0);
    IF @SupplierPaymentIdentity<@MaxSupplierPaymentId
        DBCC CHECKIDENT ('dbo.supplier_payments',RESEED) WITH NO_INFOMSGS;
    ELSE IF @SupplierPaymentIdentity<1
        DBCC CHECKIDENT ('dbo.supplier_payments',RESEED,1) WITH NO_INFOMSGS;
END;

/* Phan quyen nguoi dung. */
IF COL_LENGTH(N'dbo.Users', N'CanViewImportPrice') IS NULL ALTER TABLE dbo.Users ADD CanViewImportPrice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditImportPrice') IS NULL ALTER TABLE dbo.Users ADD CanEditImportPrice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditSellPrice') IS NULL ALTER TABLE dbo.Users ADD CanEditSellPrice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditStock') IS NULL ALTER TABLE dbo.Users ADD CanEditStock BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanDeleteInvoice') IS NULL ALTER TABLE dbo.Users ADD CanDeleteInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditProductInfo') IS NULL ALTER TABLE dbo.Users ADD CanEditProductInfo BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanImportProductExcel') IS NULL ALTER TABLE dbo.Users ADD CanImportProductExcel BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanStocktake') IS NULL ALTER TABLE dbo.Users ADD CanStocktake BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditSalesInvoice') IS NULL ALTER TABLE dbo.Users ADD CanEditSalesInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanCancelSalesInvoice') IS NULL ALTER TABLE dbo.Users ADD CanCancelSalesInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditPurchaseInvoice') IS NULL ALTER TABLE dbo.Users ADD CanEditPurchaseInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanCancelPurchaseInvoice') IS NULL ALTER TABLE dbo.Users ADD CanCancelPurchaseInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanDeletePurchaseInvoice') IS NULL ALTER TABLE dbo.Users ADD CanDeletePurchaseInvoice BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanDeletePaymentVoucher') IS NULL ALTER TABLE dbo.Users ADD CanDeletePaymentVoucher BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanManageCustomers') IS NULL ALTER TABLE dbo.Users ADD CanManageCustomers BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanManageSuppliers') IS NULL ALTER TABLE dbo.Users ADD CanManageSuppliers BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanManageCatalogs') IS NULL ALTER TABLE dbo.Users ADD CanManageCatalogs BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewAllWallet') IS NULL ALTER TABLE dbo.Users ADD CanViewAllWallet BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanTopUpWallet') IS NULL ALTER TABLE dbo.Users ADD CanTopUpWallet BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditWallet') IS NULL ALTER TABLE dbo.Users ADD CanEditWallet BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewRepairs') IS NULL ALTER TABLE dbo.Users ADD CanViewRepairs BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanEditRepairs') IS NULL ALTER TABLE dbo.Users ADD CanEditRepairs BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanUseRepairParts') IS NULL ALTER TABLE dbo.Users ADD CanUseRepairParts BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanCollectRepairPayment') IS NULL ALTER TABLE dbo.Users ADD CanCollectRepairPayment BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanCancelRepairs') IS NULL ALTER TABLE dbo.Users ADD CanCancelRepairs BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReports') IS NULL ALTER TABLE dbo.Users ADD CanViewReports BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportMoney') IS NULL ALTER TABLE dbo.Users ADD CanViewReportMoney BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportOverview') IS NULL ALTER TABLE dbo.Users ADD CanViewReportOverview BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportCollections') IS NULL ALTER TABLE dbo.Users ADD CanViewReportCollections BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportRevenue') IS NULL ALTER TABLE dbo.Users ADD CanViewReportRevenue BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportRevenueProfit') IS NULL ALTER TABLE dbo.Users ADD CanViewReportRevenueProfit BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportProducts') IS NULL ALTER TABLE dbo.Users ADD CanViewReportProducts BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportProductProfit') IS NULL ALTER TABLE dbo.Users ADD CanViewReportProductProfit BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportEmployees') IS NULL ALTER TABLE dbo.Users ADD CanViewReportEmployees BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportCashiers') IS NULL ALTER TABLE dbo.Users ADD CanViewReportCashiers BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportCustomers') IS NULL ALTER TABLE dbo.Users ADD CanViewReportCustomers BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportCustomerProfit') IS NULL ALTER TABLE dbo.Users ADD CanViewReportCustomerProfit BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewReportSuppliers') IS NULL ALTER TABLE dbo.Users ADD CanViewReportSuppliers BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanViewInventoryReport') IS NULL ALTER TABLE dbo.Users ADD CanViewInventoryReport BIT NOT NULL DEFAULT (0);
IF COL_LENGTH(N'dbo.Users', N'CanExportAccountingLedgers') IS NULL ALTER TABLE dbo.Users ADD CanExportAccountingLedgers BIT NOT NULL DEFAULT (0);

UPDATE dbo.Users
SET CanViewImportPrice=1, CanEditImportPrice=1, CanEditSellPrice=1, CanEditStock=1,
    CanDeleteInvoice=1, CanEditProductInfo=1, CanImportProductExcel=1, CanStocktake=1,
    CanEditSalesInvoice=1, CanCancelSalesInvoice=1, CanEditPurchaseInvoice=1,
    CanCancelPurchaseInvoice=1, CanDeletePurchaseInvoice=1, CanDeletePaymentVoucher=1,
    CanManageCustomers=1, CanManageSuppliers=1, CanManageCatalogs=1,
    CanViewAllWallet=1, CanTopUpWallet=1, CanEditWallet=1,
    CanViewRepairs=1, CanEditRepairs=1, CanUseRepairParts=1,
    CanCollectRepairPayment=1, CanCancelRepairs=1,
    CanViewReports=1, CanViewReportMoney=1, CanViewReportOverview=1,
    CanViewReportCollections=1, CanViewReportRevenue=1, CanViewReportRevenueProfit=1,
    CanViewReportProducts=1, CanViewReportProductProfit=1, CanViewReportEmployees=1,
    CanViewReportCashiers=1, CanViewReportCustomers=1, CanViewReportCustomerProfit=1,
    CanViewReportSuppliers=1, CanViewInventoryReport=1, CanExportAccountingLedgers=1
WHERE RoleId=1 OR LOWER(ISNULL(Username,N''))=N'admin';

/* Bien the, don vi va snapshot dong chung tu. */
IF OBJECT_ID(N'dbo.product_variants', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_variants
    (
        variant_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_variants PRIMARY KEY,
        product_id INT NOT NULL,
        sku_code NVARCHAR(80) NOT NULL,
        variant_name NVARCHAR(250) NULL,
        size_value NVARCHAR(100) NULL,
        color_value NVARCHAR(100) NULL,
        note NVARCHAR(500) NULL,
        barcode NVARCHAR(100) NULL,
        base_unit_id INT NULL,
        stock_base_qty DECIMAL(18,3) NOT NULL CONSTRAINT DF_product_variants_stock_base_qty DEFAULT (0),
        sell_price DECIMAL(18,2) NULL,
        import_price DECIMAL(18,2) NULL,
        is_default BIT NOT NULL CONSTRAINT DF_product_variants_is_default DEFAULT (0),
        is_active BIT NOT NULL CONSTRAINT DF_product_variants_is_active DEFAULT (1),
        created_at DATETIME NOT NULL CONSTRAINT DF_product_variants_created_at DEFAULT (GETDATE()),
        updated_at DATETIME NULL
    );
    CREATE UNIQUE INDEX UQ_product_variants_sku_code ON dbo.product_variants(sku_code);
END;
IF COL_LENGTH(N'dbo.product_variants', N'note') IS NULL ALTER TABLE dbo.product_variants ADD note NVARCHAR(500) NULL;
IF COL_LENGTH(N'dbo.product_variants', N'barcode') IS NULL ALTER TABLE dbo.product_variants ADD barcode NVARCHAR(100) NULL;

DECLARE @DropNegativeVariantStockCheck NVARCHAR(MAX)=N'';
SELECT @DropNegativeVariantStockCheck=@DropNegativeVariantStockCheck
    + N'ALTER TABLE dbo.product_variants DROP CONSTRAINT '+QUOTENAME(name)+N';'
FROM sys.check_constraints
WHERE parent_object_id=OBJECT_ID(N'dbo.product_variants')
  AND definition LIKE N'%stock_base_qty%';
IF LEN(@DropNegativeVariantStockCheck)>0
    EXEC sys.sp_executesql @DropNegativeVariantStockCheck;

IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_variant_attributes
    (
        attribute_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_variant_attributes PRIMARY KEY,
        variant_id INT NOT NULL,
        attribute_name NVARCHAR(100) NOT NULL,
        attribute_value NVARCHAR(200) NOT NULL,
        sort_order INT NOT NULL CONSTRAINT DF_product_variant_attributes_sort DEFAULT (0)
    );
END;

IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_unit_conversions
    (
        conversion_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_unit_conversions PRIMARY KEY,
        product_id INT NOT NULL,
        product_variant_id INT NULL,
        unit_id INT NOT NULL,
        conversion_to_base DECIMAL(18,6) NOT NULL,
        is_base BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_base DEFAULT(0),
        is_purchase_unit BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_purchase DEFAULT(1),
        is_sale_unit BIT NOT NULL CONSTRAINT DF_product_unit_conversions_is_sale DEFAULT(1),
        barcode NVARCHAR(100) NULL,
        sell_price DECIMAL(18,2) NULL,
        import_price DECIMAL(18,2) NULL,
        sort_order INT NOT NULL CONSTRAINT DF_product_unit_conversions_sort DEFAULT(0),
        is_active BIT NOT NULL CONSTRAINT DF_product_unit_conversions_active DEFAULT(1),
        created_at DATETIME NOT NULL CONSTRAINT DF_product_unit_conversions_created DEFAULT(GETDATE()),
        updated_at DATETIME NULL,
        CONSTRAINT FK_product_unit_conversions_products FOREIGN KEY(product_id) REFERENCES dbo.products(product_id),
        CONSTRAINT FK_product_unit_conversions_units FOREIGN KEY(unit_id) REFERENCES dbo.Units(unit_id),
        CONSTRAINT CK_product_unit_conversions_ratio CHECK(conversion_to_base > 0)
    );
END;
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'dbo.product_unit_conversions')
      AND name=N'IX_product_unit_conversions_product'
)
    CREATE INDEX IX_product_unit_conversions_product
        ON dbo.product_unit_conversions(product_id, product_variant_id, is_active, sort_order);

IF COL_LENGTH(N'dbo.order_items', N'product_variant_id') IS NULL ALTER TABLE dbo.order_items ADD product_variant_id INT NULL;
IF COL_LENGTH(N'dbo.order_items', N'unit_id') IS NULL ALTER TABLE dbo.order_items ADD unit_id INT NULL;
IF COL_LENGTH(N'dbo.order_items', N'input_quantity') IS NULL ALTER TABLE dbo.order_items ADD input_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.order_items', N'base_quantity') IS NULL ALTER TABLE dbo.order_items ADD base_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.order_items', N'unit_conversion_to_base') IS NULL ALTER TABLE dbo.order_items ADD unit_conversion_to_base DECIMAL(18,6) NULL;
IF COL_LENGTH(N'dbo.order_items', N'variant_name_snapshot') IS NULL ALTER TABLE dbo.order_items ADD variant_name_snapshot NVARCHAR(250) NULL;
IF COL_LENGTH(N'dbo.order_items', N'unit_name_snapshot') IS NULL ALTER TABLE dbo.order_items ADD unit_name_snapshot NVARCHAR(50) NULL;
IF COL_LENGTH(N'dbo.order_items', N'original_order_item_id') IS NULL ALTER TABLE dbo.order_items ADD original_order_item_id INT NULL;
IF COL_LENGTH(N'dbo.order_items', N'gift_quantity') IS NULL
    ALTER TABLE dbo.order_items ADD gift_quantity INT NOT NULL
        CONSTRAINT DF_order_items_gift_quantity DEFAULT(0) WITH VALUES;
IF COL_LENGTH(N'dbo.order_items', N'stock_before') IS NULL ALTER TABLE dbo.order_items ADD stock_before DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.order_items', N'stock_after') IS NULL ALTER TABLE dbo.order_items ADD stock_after DECIMAL(18,3) NULL;

UPDATE dbo.order_items
SET input_quantity=ISNULL(input_quantity, CAST(quantity AS DECIMAL(18,3))),
    base_quantity=ISNULL(base_quantity,
        CAST(CASE WHEN ISNULL(quantity,0)<0
             THEN ISNULL(quantity,0)-ISNULL(gift_quantity,0)
             ELSE ISNULL(quantity,0)+ISNULL(gift_quantity,0) END AS DECIMAL(18,3))),
    unit_conversion_to_base=ISNULL(unit_conversion_to_base, CAST(1 AS DECIMAL(18,6)))
WHERE input_quantity IS NULL OR base_quantity IS NULL OR unit_conversion_to_base IS NULL;

/* Chi tiet nhap/tra va cach xu ly tien tra NCC. */
IF COL_LENGTH(N'dbo.import_details', N'variant_id') IS NULL ALTER TABLE dbo.import_details ADD variant_id INT NULL;
IF COL_LENGTH(N'dbo.import_details', N'unit_id') IS NULL ALTER TABLE dbo.import_details ADD unit_id INT NULL;
IF COL_LENGTH(N'dbo.import_details', N'input_quantity') IS NULL ALTER TABLE dbo.import_details ADD input_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.import_details', N'base_quantity') IS NULL ALTER TABLE dbo.import_details ADD base_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.import_details', N'unit_conversion_to_base') IS NULL ALTER TABLE dbo.import_details ADD unit_conversion_to_base DECIMAL(18,6) NULL;

UPDATE dbo.import_details
SET unit_conversion_to_base=ISNULL(unit_conversion_to_base,1),
    input_quantity=ISNULL(input_quantity,quantity),
    base_quantity=ISNULL(base_quantity,quantity)
WHERE unit_conversion_to_base IS NULL OR input_quantity IS NULL OR base_quantity IS NULL;

IF COL_LENGTH(N'dbo.imports', N'supplier_credit_applied') IS NULL
    ALTER TABLE dbo.imports ADD supplier_credit_applied DECIMAL(18,0) NOT NULL
        CONSTRAINT DF_imports_supplier_credit_applied DEFAULT(0);
IF COL_LENGTH(N'dbo.imports', N'supplier_refund_received') IS NULL
    ALTER TABLE dbo.imports ADD supplier_refund_received DECIMAL(18,0) NOT NULL
        CONSTRAINT DF_imports_supplier_refund_received DEFAULT(0);

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID(N'dbo.imports')
      AND definition LIKE N'%supplier_credit_applied%'
)
    ALTER TABLE dbo.imports WITH CHECK
        ADD CONSTRAINT CK_imports_supplier_credit_applied_nonnegative
        CHECK(supplier_credit_applied>=0);
IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID(N'dbo.imports')
      AND definition LIKE N'%supplier_refund_received%'
)
    ALTER TABLE dbo.imports WITH CHECK
        ADD CONSTRAINT CK_imports_supplier_refund_received_nonnegative
        CHECK(supplier_refund_received>=0);

IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_id') IS NULL ALTER TABLE dbo.purchase_return_details ADD unit_id INT NULL;
    IF COL_LENGTH(N'dbo.purchase_return_details', N'input_quantity') IS NULL ALTER TABLE dbo.purchase_return_details ADD input_quantity DECIMAL(18,3) NULL;
    IF COL_LENGTH(N'dbo.purchase_return_details', N'base_quantity') IS NULL ALTER TABLE dbo.purchase_return_details ADD base_quantity DECIMAL(18,3) NULL;
    IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_conversion_to_base') IS NULL ALTER TABLE dbo.purchase_return_details ADD unit_conversion_to_base DECIMAL(18,6) NULL;
    IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_name_snapshot') IS NULL ALTER TABLE dbo.purchase_return_details ADD unit_name_snapshot NVARCHAR(50) NULL;
END;

IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.purchase_returns', N'settlement_type') IS NULL
        ALTER TABLE dbo.purchase_returns ADD settlement_type NVARCHAR(20) NOT NULL
            CONSTRAINT DF_purchase_returns_settlement_type DEFAULT(N'DEBT_OFFSET');
    IF COL_LENGTH(N'dbo.purchase_returns', N'refund_method') IS NULL
        ALTER TABLE dbo.purchase_returns ADD refund_method NVARCHAR(50) NULL;
END;

IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
    UPDATE prd
    SET unit_id=ISNULL(prd.unit_id,ISNULL(id.unit_id,p.unit_id)),
        input_quantity=ISNULL(prd.input_quantity,CAST(prd.quantity AS DECIMAL(18,3))),
        unit_conversion_to_base=ISNULL(prd.unit_conversion_to_base,ISNULL(NULLIF(id.unit_conversion_to_base,0),1)),
        base_quantity=ISNULL(prd.base_quantity,
            CAST(prd.quantity AS DECIMAL(18,3))*ISNULL(NULLIF(id.unit_conversion_to_base,0),1)),
        unit_name_snapshot=ISNULL(NULLIF(prd.unit_name_snapshot,N''''),u.unit_name)
    FROM dbo.purchase_return_details prd
    LEFT JOIN dbo.import_details id ON id.import_detail_id=prd.import_detail_id
    LEFT JOIN dbo.products p ON p.product_id=prd.product_id
    LEFT JOIN dbo.Units u ON u.unit_id=ISNULL(id.unit_id,p.unit_id)
    WHERE prd.unit_id IS NULL OR prd.input_quantity IS NULL OR prd.base_quantity IS NULL
       OR prd.unit_conversion_to_base IS NULL OR NULLIF(prd.unit_name_snapshot,N'''') IS NULL;';
END;

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_key_columns fkc
    INNER JOIN sys.columns c ON c.object_id=fkc.parent_object_id AND c.column_id=fkc.parent_column_id
    WHERE fkc.parent_object_id=OBJECT_ID(N'dbo.import_details')
      AND fkc.referenced_object_id=OBJECT_ID(N'dbo.product_variants')
      AND c.name=N'variant_id'
)
BEGIN
    IF EXISTS
    (
        SELECT 1 FROM dbo.import_details d
        LEFT JOIN dbo.product_variants v ON v.variant_id=d.variant_id
        WHERE d.variant_id IS NOT NULL AND v.variant_id IS NULL
    )
        ALTER TABLE dbo.import_details WITH NOCHECK
            ADD CONSTRAINT FK_import_details_variant_id FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);
    ELSE
        ALTER TABLE dbo.import_details WITH CHECK
            ADD CONSTRAINT FK_import_details_variant_id FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);

    ALTER TABLE dbo.import_details CHECK CONSTRAINT FK_import_details_variant_id;
END;

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID(N'dbo.import_details') AND name=N'IX_import_details_variant_id'
)
    CREATE INDEX IX_import_details_variant_id ON dbo.import_details(variant_id);

/* Cong no khach hang. */
IF OBJECT_ID(N'dbo.customer_debt_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customer_debt_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_customer_debt_adjustments PRIMARY KEY,
        customer_id INT NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_customer_debt_adjustments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        adjustment_type NVARCHAR(30) NOT NULL CONSTRAINT DF_customer_debt_adjustments_type DEFAULT(N'DISCOUNT'),
        employee_id INT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_customer_debt_adjustments_created DEFAULT(GETDATE()),
        CONSTRAINT CK_customer_debt_adjustments_amount CHECK(amount>0)
    );
END;
IF OBJECT_ID(N'dbo.customer_debt_discount_allocations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.customer_debt_discount_allocations
    (
        allocation_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_customer_debt_discount_allocations PRIMARY KEY,
        adjustment_id INT NOT NULL,
        order_id INT NOT NULL,
        amount DECIMAL(18,0) NOT NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_customer_debt_discount_allocations_created DEFAULT(GETDATE()),
        CONSTRAINT CK_customer_debt_discount_allocations_amount CHECK(amount>0),
        CONSTRAINT UQ_customer_debt_discount_allocations_adjustment_order UNIQUE(adjustment_id,order_id)
    );
END;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.customer_debt_adjustments') AND name=N'IX_customer_debt_adjustments_customer_date')
    CREATE INDEX IX_customer_debt_adjustments_customer_date ON dbo.customer_debt_adjustments(customer_id,adjustment_date,adjustment_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.customer_debt_discount_allocations') AND name=N'IX_customer_debt_discount_allocations_order')
    CREATE INDEX IX_customer_debt_discount_allocations_order ON dbo.customer_debt_discount_allocations(order_id,adjustment_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_customer_debt_adjustments_customers')
    ALTER TABLE dbo.customer_debt_adjustments WITH CHECK ADD CONSTRAINT FK_customer_debt_adjustments_customers FOREIGN KEY(customer_id) REFERENCES dbo.customers(customer_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_customer_debt_adjustments_employees')
    ALTER TABLE dbo.customer_debt_adjustments WITH CHECK ADD CONSTRAINT FK_customer_debt_adjustments_employees FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_customer_debt_discount_allocations_adjustment')
    ALTER TABLE dbo.customer_debt_discount_allocations WITH CHECK ADD CONSTRAINT FK_customer_debt_discount_allocations_adjustment FOREIGN KEY(adjustment_id) REFERENCES dbo.customer_debt_adjustments(adjustment_id) ON DELETE CASCADE;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_customer_debt_discount_allocations_order')
    ALTER TABLE dbo.customer_debt_discount_allocations WITH CHECK ADD CONSTRAINT FK_customer_debt_discount_allocations_order FOREIGN KEY(order_id) REFERENCES dbo.orders(order_id);

/* Cong no nha cung cap. */
IF OBJECT_ID(N'dbo.supplier_debt_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.supplier_debt_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_supplier_debt_adjustments PRIMARY KEY,
        supplier_id INT NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_supplier_debt_adjustments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        adjustment_type NVARCHAR(30) NOT NULL CONSTRAINT DF_supplier_debt_adjustments_type DEFAULT(N'DISCOUNT'),
        employee_id INT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_supplier_debt_adjustments_created DEFAULT(GETDATE()),
        CONSTRAINT CK_supplier_debt_adjustments_amount CHECK(amount>0)
    );
END;
IF OBJECT_ID(N'dbo.supplier_debt_discount_allocations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.supplier_debt_discount_allocations
    (
        allocation_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_supplier_debt_discount_allocations PRIMARY KEY,
        adjustment_id INT NOT NULL,
        import_id INT NOT NULL,
        amount DECIMAL(18,0) NOT NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_supplier_debt_discount_allocations_created DEFAULT(GETDATE()),
        CONSTRAINT CK_supplier_debt_discount_allocations_amount CHECK(amount>0),
        CONSTRAINT UQ_supplier_debt_discount_allocations_adjustment_import UNIQUE(adjustment_id,import_id)
    );
END;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.supplier_debt_adjustments') AND name=N'IX_supplier_debt_adjustments_supplier_date')
    CREATE INDEX IX_supplier_debt_adjustments_supplier_date ON dbo.supplier_debt_adjustments(supplier_id,adjustment_date,adjustment_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.supplier_debt_discount_allocations') AND name=N'IX_supplier_debt_discount_allocations_import')
    CREATE INDEX IX_supplier_debt_discount_allocations_import ON dbo.supplier_debt_discount_allocations(import_id,adjustment_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_supplier_debt_adjustments_suppliers')
    ALTER TABLE dbo.supplier_debt_adjustments WITH CHECK ADD CONSTRAINT FK_supplier_debt_adjustments_suppliers FOREIGN KEY(supplier_id) REFERENCES dbo.suppliers(supplier_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_supplier_debt_adjustments_employees')
    ALTER TABLE dbo.supplier_debt_adjustments WITH CHECK ADD CONSTRAINT FK_supplier_debt_adjustments_employees FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_supplier_debt_discount_allocations_adjustment')
    ALTER TABLE dbo.supplier_debt_discount_allocations WITH CHECK ADD CONSTRAINT FK_supplier_debt_discount_allocations_adjustment FOREIGN KEY(adjustment_id) REFERENCES dbo.supplier_debt_adjustments(adjustment_id) ON DELETE CASCADE;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_supplier_debt_discount_allocations_import')
    ALTER TABLE dbo.supplier_debt_discount_allocations WITH CHECK ADD CONSTRAINT FK_supplier_debt_discount_allocations_import FOREIGN KEY(import_id) REFERENCES dbo.imports(import_id);

/* Luong nhan vien. */
IF OBJECT_ID(N'dbo.employee_payroll_settings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_settings
    (
        employee_id INT NOT NULL CONSTRAINT PK_employee_payroll_settings PRIMARY KEY,
        base_salary DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payroll_settings_base DEFAULT(0),
        commission_rate DECIMAL(9,4) NOT NULL CONSTRAINT DF_employee_payroll_settings_rate DEFAULT(0),
        updated_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_settings_updated DEFAULT(GETDATE()),
        updated_by NVARCHAR(100) NULL
    );
END;
IF OBJECT_ID(N'dbo.employee_payrolls', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payrolls
    (
        payroll_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payrolls PRIMARY KEY,
        payroll_month DATE NOT NULL,
        employee_id INT NOT NULL,
        employee_name NVARCHAR(200) NOT NULL,
        role_name NVARCHAR(100) NULL,
        base_salary DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_base DEFAULT(0),
        revenue_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_revenue DEFAULT(0),
        commission_rate DECIMAL(9,4) NOT NULL CONSTRAINT DF_employee_payrolls_rate DEFAULT(0),
        commission_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_commission DEFAULT(0),
        repair_commission_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_employee_payrolls_repair_commission DEFAULT(0),
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payrolls_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        updated_at DATETIME NOT NULL CONSTRAINT DF_employee_payrolls_updated DEFAULT(GETDATE()),
        updated_by NVARCHAR(100) NULL,
        CONSTRAINT UQ_employee_payrolls_month_employee UNIQUE(payroll_month,employee_id)
    );
END;
IF COL_LENGTH(N'dbo.employee_payrolls', N'repair_commission_amount') IS NULL
    ALTER TABLE dbo.employee_payrolls ADD repair_commission_amount DECIMAL(18,0) NOT NULL
        CONSTRAINT DF_employee_payrolls_repair_commission DEFAULT(0);
IF OBJECT_ID(N'dbo.employee_payroll_adjustments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_adjustments
    (
        adjustment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payroll_adjustments PRIMARY KEY,
        payroll_id INT NOT NULL,
        adjustment_type NVARCHAR(20) NOT NULL,
        adjustment_date DATETIME NOT NULL CONSTRAINT DF_employee_payroll_adjustments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        note NVARCHAR(500) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_adjustments_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        is_void BIT NOT NULL CONSTRAINT DF_employee_payroll_adjustments_void DEFAULT(0),
        voided_at DATETIME NULL,
        voided_by NVARCHAR(100) NULL,
        CONSTRAINT CK_employee_payroll_adjustments_type CHECK(adjustment_type IN(N'ALLOWANCE',N'BONUS',N'DEDUCTION')),
        CONSTRAINT CK_employee_payroll_adjustments_amount CHECK(amount>0)
    );
END;
IF OBJECT_ID(N'dbo.employee_payroll_payments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.employee_payroll_payments
    (
        payment_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_employee_payroll_payments PRIMARY KEY,
        payroll_id INT NOT NULL,
        payment_type NVARCHAR(20) NOT NULL,
        payment_date DATETIME NOT NULL CONSTRAINT DF_employee_payroll_payments_date DEFAULT(GETDATE()),
        amount DECIMAL(18,0) NOT NULL,
        payment_method NVARCHAR(50) NULL,
        note NVARCHAR(500) NULL,
        reference_code NVARCHAR(100) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_employee_payroll_payments_created DEFAULT(GETDATE()),
        created_by NVARCHAR(100) NULL,
        is_void BIT NOT NULL CONSTRAINT DF_employee_payroll_payments_void DEFAULT(0),
        voided_at DATETIME NULL,
        voided_by NVARCHAR(100) NULL,
        CONSTRAINT CK_employee_payroll_payments_type CHECK(payment_type IN(N'ADVANCE',N'SETTLEMENT')),
        CONSTRAINT CK_employee_payroll_payments_amount CHECK(amount>0)
    );
END;

IF OBJECT_ID(N'dbo.employee_payroll_adjustments', N'U') IS NOT NULL
BEGIN
    DECLARE @DropOldPayrollAdjustmentCheck NVARCHAR(MAX)=N'';
    SELECT @DropOldPayrollAdjustmentCheck=@DropOldPayrollAdjustmentCheck
        + N'ALTER TABLE dbo.employee_payroll_adjustments DROP CONSTRAINT '+QUOTENAME(name)+N';'
    FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID(N'dbo.employee_payroll_adjustments')
      AND definition LIKE N'%adjustment_type%'
      AND definition LIKE N'%BONUS%'
      AND definition LIKE N'%DEDUCTION%'
      AND definition NOT LIKE N'%ALLOWANCE%';
    IF LEN(@DropOldPayrollAdjustmentCheck)>0
        EXEC sys.sp_executesql @DropOldPayrollAdjustmentCheck;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id=OBJECT_ID(N'dbo.employee_payroll_adjustments')
          AND definition LIKE N'%adjustment_type%'
          AND definition LIKE N'%ALLOWANCE%'
          AND definition LIKE N'%BONUS%'
          AND definition LIKE N'%DEDUCTION%'
    )
        ALTER TABLE dbo.employee_payroll_adjustments WITH CHECK
            ADD CONSTRAINT CK_employee_payroll_adjustments_type
            CHECK(adjustment_type IN(N'ALLOWANCE',N'BONUS',N'DEDUCTION'));
END;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_employee_payroll_settings_employee')
    ALTER TABLE dbo.employee_payroll_settings WITH CHECK ADD CONSTRAINT FK_employee_payroll_settings_employee FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_employee_payrolls_employee')
    ALTER TABLE dbo.employee_payrolls WITH CHECK ADD CONSTRAINT FK_employee_payrolls_employee FOREIGN KEY(employee_id) REFERENCES dbo.employees(employee_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_employee_payroll_adjustments_payroll')
    ALTER TABLE dbo.employee_payroll_adjustments WITH CHECK ADD CONSTRAINT FK_employee_payroll_adjustments_payroll FOREIGN KEY(payroll_id) REFERENCES dbo.employee_payrolls(payroll_id);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_employee_payroll_payments_payroll')
    ALTER TABLE dbo.employee_payroll_payments WITH CHECK ADD CONSTRAINT FK_employee_payroll_payments_payroll FOREIGN KEY(payroll_id) REFERENCES dbo.employee_payrolls(payroll_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.employee_payrolls') AND name=N'IX_employee_payrolls_month_employee')
    CREATE INDEX IX_employee_payrolls_month_employee ON dbo.employee_payrolls(payroll_month,employee_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.employee_payroll_adjustments') AND name=N'IX_employee_payroll_adjustments_payroll')
    CREATE INDEX IX_employee_payroll_adjustments_payroll ON dbo.employee_payroll_adjustments(payroll_id,is_void,adjustment_date);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.employee_payroll_payments') AND name=N'IX_employee_payroll_payments_payroll')
    CREATE INDEX IX_employee_payroll_payments_payroll ON dbo.employee_payroll_payments(payroll_id,is_void,payment_date);

IF IDENT_CURRENT(N'dbo.employee_payrolls')<1
    DBCC CHECKIDENT ('dbo.employee_payrolls',RESEED,1) WITH NO_INFOMSGS;
IF IDENT_CURRENT(N'dbo.employee_payroll_adjustments')<1
    DBCC CHECKIDENT ('dbo.employee_payroll_adjustments',RESEED,1) WITH NO_INFOMSGS;
IF IDENT_CURRENT(N'dbo.employee_payroll_payments')<1
    DBCC CHECKIDENT ('dbo.employee_payroll_payments',RESEED,1) WITH NO_INFOMSGS;

/* Xac nhan cac migration lon da tao du schema truoc khi ung dung tat DDL luc chay. */
IF OBJECT_ID(N'dbo.repair_orders', N'U') IS NULL
   OR OBJECT_ID(N'dbo.repair_order_items', N'U') IS NULL
   OR OBJECT_ID(N'dbo.product_batches', N'U') IS NULL
   OR OBJECT_ID(N'dbo.order_item_batches', N'U') IS NULL
   OR OBJECT_ID(N'dbo.purchase_return_detail_batches', N'U') IS NULL
   OR OBJECT_ID(N'dbo.batch_inventory_movements', N'U') IS NULL
   OR COL_LENGTH(N'dbo.orders', N'is_delivery') IS NULL
   OR COL_LENGTH(N'dbo.employees', N'bank_account') IS NULL
BEGIN
    THROW 51251, N'Con thieu migration sua chua, lo/HSD, giao hang hoac tai khoan nhan vien.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM (VALUES
        (N'products',N'stock'),
        (N'order_items',N'quantity'),
        (N'import_details',N'quantity'),
        (N'purchase_return_details',N'quantity'),
        (N'inventory_check_details',N'system_stock'),
        (N'inventory_check_details',N'actual_stock'),
        (N'inventory_check_details',N'difference')
    ) q(table_name,column_name)
    LEFT JOIN sys.columns c
      ON c.object_id=OBJECT_ID(N'dbo.'+q.table_name)
     AND c.name=q.column_name
    WHERE c.column_id IS NULL
       OR TYPE_NAME(c.user_type_id)<>N'decimal'
       OR c.precision<>18
       OR c.scale<>3
)
BEGIN
    THROW 51252, N'Migration so luong thap phan chua duoc ap dung day du.', 1;
END;
