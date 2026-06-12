/*
    MigrationId: 2026-06-12-database-reset-purchase-return-fix
    Mục đích: Bổ sung bảng Trả hàng NCC vào lệnh reset dữ liệu.
    Ghi chú: Giữ lại bảng hệ thống/cấu hình/tài khoản như phiên bản cũ.
*/

IF OBJECT_ID(N'dbo.Database_ResetData', N'P') IS NULL
BEGIN
    EXEC(N'CREATE PROCEDURE dbo.Database_ResetData AS BEGIN SET NOCOUNT ON; END');
END
GO

ALTER PROCEDURE [dbo].[Database_ResetData]
    @Confirm NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(@Confirm, N'') <> N'RESET'
    BEGIN
        THROW 50001, N'Vui lòng truyền @Confirm = N''RESET'' để xác nhận xóa dữ liệu.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        --------------------------------------------------------------------
        -- GIỮ LẠI CÁC BẢNG HỆ THỐNG / CẤU HÌNH / ĐĂNG NHẬP:
        -- __AppSqlMigrations, __TestOnlineUpdate, Roles, Users,
        -- employees, StoreInfo, Units
        --------------------------------------------------------------------

        --------------------------------------------------------------------
        -- 1) XÓA BẢNG CON / CHI TIẾT GIAO DỊCH TRƯỚC
        --------------------------------------------------------------------
        IF OBJECT_ID(N'dbo.order_items', N'U') IS NOT NULL
            DELETE FROM dbo.order_items;

        -- MỚI: Chi tiết trả hàng nhà cung cấp phải xóa trước phiếu trả NCC,
        -- import_details, products.
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

        --------------------------------------------------------------------
        -- 2) XÓA BẢNG CHA GIAO DỊCH
        --------------------------------------------------------------------
        -- MỚI: Phiếu trả hàng NCC phải xóa trước imports, suppliers.
        IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
            DELETE FROM dbo.purchase_returns;

        IF OBJECT_ID(N'dbo.orders', N'U') IS NOT NULL
            DELETE FROM dbo.orders;

        IF OBJECT_ID(N'dbo.imports', N'U') IS NOT NULL
            DELETE FROM dbo.imports;

        IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
            DELETE FROM dbo.inventory_checks;

        --------------------------------------------------------------------
        -- 3) XÓA DỮ LIỆU BIẾN THỂ / ĐƠN VỊ QUY ĐỔI SẢN PHẨM
        --------------------------------------------------------------------
        IF OBJECT_ID(N'dbo.product_unit_conversions', N'U') IS NOT NULL
            DELETE FROM dbo.product_unit_conversions;

        IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NOT NULL
            DELETE FROM dbo.product_variant_attributes;

        IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
            DELETE FROM dbo.product_variants;

        --------------------------------------------------------------------
        -- 4) XÓA MASTER DATA NGHIỆP VỤ
        -- Giữ Units, StoreInfo, Roles, Users, employees.
        --------------------------------------------------------------------
        IF OBJECT_ID(N'dbo.products', N'U') IS NOT NULL
            DELETE FROM dbo.products;

        IF OBJECT_ID(N'dbo.customers', N'U') IS NOT NULL
            DELETE FROM dbo.customers;

        IF OBJECT_ID(N'dbo.suppliers', N'U') IS NOT NULL
            DELETE FROM dbo.suppliers;

        IF OBJECT_ID(N'dbo.categories', N'U') IS NOT NULL
            DELETE FROM dbo.categories;

        --------------------------------------------------------------------
        -- 5) RESET IDENTITY VỀ 0 ĐỂ ITEM TIẾP THEO LÀ 1
        --------------------------------------------------------------------
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
