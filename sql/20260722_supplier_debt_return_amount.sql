/* Hotfix 2026-07-22
   - Show supplier debt per import after supplier returns.
   - Keep the legacy sp_GetSupplierDebt formula aligned with SupplierPayments_GetDebt.

   Safe to run on an existing customer database. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.Imports_GetBySupplier', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Imports_GetBySupplier AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[Imports_GetBySupplier]
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
        ISNULL((
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
END
GO

IF OBJECT_ID(N'dbo.sp_GetSupplierDebt', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_GetSupplierDebt AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[sp_GetSupplierDebt]
    @supplier_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ImportDebt DECIMAL(18,0) = ISNULL((
        SELECT SUM(
            CASE
                WHEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0) > 0
                    THEN ISNULL(i.final_amount, 0) - ISNULL(i.paid_amount, 0) - ISNULL(r.ReturnedAmount, 0)
                ELSE 0
            END
        )
        FROM dbo.imports i
        OUTER APPLY
        (
            SELECT SUM(ISNULL(pr.total_amount, 0)) AS ReturnedAmount
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE i.supplier_id = @supplier_id
          AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    DECLARE @TotalPaidAfter DECIMAL(18,0) = ISNULL((
        SELECT SUM(ISNULL(amount, 0))
        FROM dbo.supplier_payments
        WHERE supplier_id = @supplier_id
    ), 0);

    DECLARE @CurrentDebt DECIMAL(18,0) = @ImportDebt - @TotalPaidAfter;
    IF @CurrentDebt < 0 SET @CurrentDebt = 0;

    SELECT @CurrentDebt AS CurrentDebt;
END
GO
