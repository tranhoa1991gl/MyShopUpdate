IF OBJECT_ID(N'dbo.Database_ResetData', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Database_ResetData AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Database_ResetData]
    @Confirm NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@Confirm, N'') <> N'RESET'
    BEGIN
        THROW 50001, N'Vui long truyen @Confirm = N''RESET'' de xac nhan xoa du lieu.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NOT NULL
            DELETE FROM dbo.customer_wallet_transactions;

        IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
            DELETE FROM dbo.order_items;

        IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NOT NULL
            DELETE FROM dbo.purchase_return_details;

        IF OBJECT_ID(N'dbo.product_serials', N'U') IS NOT NULL
            DELETE FROM dbo.product_serials;

        IF OBJECT_ID(N'dbo.customer_payments', N'U') IS NOT NULL
            DELETE FROM dbo.customer_payments;

        IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
            DELETE FROM dbo.supplier_payments;

        IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
            DELETE FROM dbo.import_details;

        IF OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NOT NULL
            DELETE FROM dbo.inventory_check_details;

        IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NOT NULL
            DELETE FROM dbo.product_unit_conversions;

        IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NOT NULL
            DELETE FROM dbo.product_variant_attributes;

        IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
            DELETE FROM dbo.purchase_returns;

        IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
            DELETE FROM dbo.orders;

        IF OBJECT_ID(N'dbo.imports', N'U') IS NOT NULL
            DELETE FROM dbo.imports;

        IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
            DELETE FROM dbo.inventory_checks;

        IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
            DELETE FROM dbo.product_variants;

        IF OBJECT_ID(N'dbo.products', N'U') IS NOT NULL
            DELETE FROM dbo.products;

        IF OBJECT_ID(N'dbo.customers', N'U') IS NOT NULL
            DELETE FROM dbo.customers;

        IF OBJECT_ID(N'dbo.suppliers', N'U') IS NOT NULL
            DELETE FROM dbo.suppliers;

        IF OBJECT_ID(N'dbo.categories', N'U') IS NOT NULL
            DELETE FROM dbo.categories;

        IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
            DELETE FROM dbo.Users;

        IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
            DELETE FROM dbo.employees;

        IF OBJECT_ID(N'dbo.Roles', N'U') IS NOT NULL
            DELETE FROM dbo.Roles;

        IF OBJECT_ID(N'dbo.StoreInfo', N'U') IS NOT NULL
            DELETE FROM dbo.StoreInfo;

        IF OBJECT_ID(N'dbo.Units', N'U') IS NOT NULL
            DELETE FROM dbo.Units;

        IF OBJECT_ID(N'dbo.__TestOnlineUpdate', N'U') IS NOT NULL
            DELETE FROM dbo.__TestOnlineUpdate;

        IF OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.customer_wallet_transactions', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.order_items', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.purchase_return_details', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.purchase_returns', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.product_serials', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.product_serials', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.customer_payments', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.customer_payments', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.supplier_payments', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.supplier_payments', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.import_details', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.inventory_check_details', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.orders', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.imports', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.imports', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.inventory_checks', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.product_unit_conversions', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.product_variant_attributes', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.product_variants', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.products', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.products', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.customers', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.customers', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.suppliers', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.suppliers', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.categories', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.categories', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.Users', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.employees', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.employees', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.StoreInfo', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.StoreInfo', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.Units', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.Units', RESEED, 0) WITH NO_INFOMSGS;
        IF OBJECT_ID(N'dbo.__TestOnlineUpdate', N'U') IS NOT NULL
            DBCC CHECKIDENT ('dbo.__TestOnlineUpdate', RESEED, 0) WITH NO_INFOMSGS;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        THROW 50002, @Err, 1;
    END CATCH
END
GO
