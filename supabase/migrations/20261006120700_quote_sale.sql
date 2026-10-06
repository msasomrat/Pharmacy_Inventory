-- =============================================================================
-- Migration: quote_sale
-- Exact price preview for the POS. Runs create_sale inside a subtransaction and always rolls it
-- back, so the counter shows the server's own figures (FEFO batch prices, discounts, loyalty, rounding)
-- without persisting anything: no sale, no stock movement, no invoice number is consumed.
-- =============================================================================

create or replace function public.quote_sale(
  p_branch_id uuid,
  p_items jsonb,
  p_customer_id uuid default null,
  p_loyalty_card_no text default null,
  p_invoice_discount_paisa bigint default 0,
  p_prescription jsonb default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sale jsonb;
  v_quote text;
begin
  begin
    -- A large cash tender makes the quote independent of payment; the sale is rolled back below.
    v_sale := public.create_sale(
      p_branch_id, p_items,
      jsonb_build_array(jsonb_build_object('method', 'cash', 'amount_paisa', 100000000000)),
      gen_random_uuid(), p_customer_id, p_loyalty_card_no, p_invoice_discount_paisa, p_prescription, null);

    select jsonb_build_object(
             'gross_paisa', s.gross_paisa,
             'discount_paisa', s.line_discount_paisa + s.invoice_discount_paisa,
             'loyalty_discount_paisa', s.loyalty_discount_paisa,
             'rounding_paisa', s.rounding_paisa,
             'total_paisa', s.total_paisa,
             'vat_included_paisa', s.vat_included_paisa,
             'points_earned', s.points_earned,
             'lines', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'medicine_id', i.medicine_id, 'quantity', i.quantity, 'gross_paisa', i.gross_paisa,
                        'discount_paisa', i.line_discount_paisa + i.invoice_discount_paisa,
                        'loyalty_discount_paisa', i.loyalty_discount_paisa, 'net_paisa', i.net_paisa)
                      order by i.line_no)
                 from public.sale_items i where i.sale_id = s.id), '[]'::jsonb))::text
      into v_quote
      from public.sales s
     where s.id = (v_sale ->> 'sale_id')::uuid;

    raise exception using errcode = 'PQ000', message = v_quote;
  exception
    when sqlstate 'PQ000' then
      get stacked diagnostics v_quote = message_text;
  end;
  return v_quote::jsonb;
end;
$$;

grant execute on function public.quote_sale(uuid, jsonb, uuid, text, bigint, jsonb) to authenticated;

call app.harden_privileges();
