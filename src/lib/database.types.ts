
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "public": {
          Tables: {
            "batches": {
                  Row: {
                    "batch_no": string,"branch_id": string,"cost_paisa": number,"created_at": string,"created_by": string | null,"expiry_date": string,"id": string,"is_depleted": boolean | null,"medicine_id": string,"mrp_paisa": number,"organization_id": string,"quantity_on_hand": number,"received_at": string,"sale_price_paisa": number,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_no": string,"branch_id": string,"cost_paisa": number,"created_at"?: string,"created_by"?: string | null,"expiry_date": string,"id"?: string,"is_depleted"?: never,"medicine_id": string,"mrp_paisa": number,"organization_id": string,"quantity_on_hand"?: number,"received_at"?: string,"sale_price_paisa": number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "batch_no"?: string,"branch_id"?: string,"cost_paisa"?: number,"created_at"?: string,"created_by"?: string | null,"expiry_date"?: string,"id"?: string,"is_depleted"?: never,"medicine_id"?: string,"mrp_paisa"?: number,"organization_id"?: string,"quantity_on_hand"?: number,"received_at"?: string,"sale_price_paisa"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "batches_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "batches_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"branch_assignments": {
                  Row: {
                    "branch_id": string,"created_at": string,"created_by": string | null,"id": string,"organization_id": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"organization_id": string,"user_id": string
                  }
                  Update: {
                    "branch_id"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"organization_id"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "branch_assignments_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"branch_medicine_settings": {
                  Row: {
                    "branch_id": string,"max_stock_level": number | null,"medicine_id": string,"organization_id": string,"rack_location": string | null,"reorder_level": number,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"max_stock_level"?: number | null,"medicine_id": string,"organization_id": string,"rack_location"?: string | null,"reorder_level"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "branch_id"?: string,"max_stock_level"?: number | null,"medicine_id"?: string,"organization_id"?: string,"rack_location"?: string | null,"reorder_level"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "branch_medicine_settings_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "branch_medicine_settings_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"branches": {
                  Row: {
                    "address": string | null,"code": string,"created_at": string,"created_by": string | null,"id": string,"is_active": boolean,"name": string,"organization_id": string,"phone": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"code": string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name": string,"organization_id": string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "address"?: string | null,"code"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name"?: string,"organization_id"?: string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "branches_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"controlled_drug_register": {
                  Row: {
                    "branch_id": string,"created_at": string,"created_by": string | null,"doctor_name": string | null,"doctor_reg_no": string | null,"entry_type": string,"id": number,"medicine_id": string,"organization_id": string,"patient_name": string | null,"prescription_id": string | null,"quantity": number,"sale_id": string,"sale_item_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"created_at"?: string,"created_by"?: string | null,"doctor_name"?: string | null,"doctor_reg_no"?: string | null,"entry_type": string,"id"?: never,"medicine_id": string,"organization_id": string,"patient_name"?: string | null,"prescription_id"?: string | null,"quantity": number,"sale_id": string,"sale_item_id": string
                  }
                  Update: {
                    "branch_id"?: string,"created_at"?: string,"created_by"?: string | null,"doctor_name"?: string | null,"doctor_reg_no"?: string | null,"entry_type"?: string,"id"?: never,"medicine_id"?: string,"organization_id"?: string,"patient_name"?: string | null,"prescription_id"?: string | null,"quantity"?: number,"sale_id"?: string,"sale_item_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "controlled_drug_register_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "controlled_drug_register_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "controlled_drug_register_organization_id_prescription_id_fkey"
      columns: ["organization_id","prescription_id"]
isOneToOne: false
      referencedRelation: "prescriptions"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "controlled_drug_register_organization_id_sale_id_fkey"
      columns: ["organization_id","sale_id"]
isOneToOne: false
      referencedRelation: "sales"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "controlled_drug_register_organization_id_sale_item_id_fkey"
      columns: ["organization_id","sale_item_id"]
isOneToOne: false
      referencedRelation: "sale_items"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"customer_ledger_entries": {
                  Row: {
                    "amount_paisa": number,"branch_id": string | null,"client_request_id": string | null,"created_at": string,"created_by": string | null,"customer_id": string,"entry_type": string,"id": number,"method": Database["public"]['Enums']["payment_method"] | null,"note": string | null,"organization_id": string,"reference_id": string | null,"reference_type": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paisa": number,"branch_id"?: string | null,"client_request_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"customer_id": string,"entry_type": string,"id"?: never,"method"?: Database["public"]['Enums']["payment_method"] | null,"note"?: string | null,"organization_id": string,"reference_id"?: string | null,"reference_type"?: string | null
                  }
                  Update: {
                    "amount_paisa"?: number,"branch_id"?: string | null,"client_request_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"customer_id"?: string,"entry_type"?: string,"id"?: never,"method"?: Database["public"]['Enums']["payment_method"] | null,"note"?: string | null,"organization_id"?: string,"reference_id"?: string | null,"reference_type"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "customer_ledger_entries_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "customer_ledger_entries_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customer_balances"
      referencedColumns: ["organization_id","customer_id"]
    },{
      foreignKeyName: "customer_ledger_entries_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"customers": {
                  Row: {
                    "address": string | null,"created_at": string,"created_by": string | null,"credit_limit_paisa": number,"id": string,"is_active": boolean,"name": string,"notes": string | null,"organization_id": string,"phone": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"created_at"?: string,"created_by"?: string | null,"credit_limit_paisa"?: number,"id"?: string,"is_active"?: boolean,"name": string,"notes"?: string | null,"organization_id": string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "address"?: string | null,"created_at"?: string,"created_by"?: string | null,"credit_limit_paisa"?: number,"id"?: string,"is_active"?: boolean,"name"?: string,"notes"?: string | null,"organization_id"?: string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "customers_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"daily_branch_sales": {
                  Row: {
                    "branch_id": string,"business_date": string,"cost_paisa": number,"credit_sales_paisa": number,"discount_paisa": number,"gross_paisa": number,"loyalty_discount_paisa": number,"net_paisa": number,"organization_id": string,"returns_cost_paisa": number,"returns_count": number,"returns_paisa": number,"sales_count": number,"voided_cost_paisa": number,"voided_paisa": number,"voids_count": number
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"business_date": string,"cost_paisa"?: number,"credit_sales_paisa"?: number,"discount_paisa"?: number,"gross_paisa"?: number,"loyalty_discount_paisa"?: number,"net_paisa"?: number,"organization_id": string,"returns_cost_paisa"?: number,"returns_count"?: number,"returns_paisa"?: number,"sales_count"?: number,"voided_cost_paisa"?: number,"voided_paisa"?: number,"voids_count"?: number
                  }
                  Update: {
                    "branch_id"?: string,"business_date"?: string,"cost_paisa"?: number,"credit_sales_paisa"?: number,"discount_paisa"?: number,"gross_paisa"?: number,"loyalty_discount_paisa"?: number,"net_paisa"?: number,"organization_id"?: string,"returns_cost_paisa"?: number,"returns_count"?: number,"returns_paisa"?: number,"sales_count"?: number,"voided_cost_paisa"?: number,"voided_paisa"?: number,"voids_count"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "daily_branch_sales_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"generics": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"is_active": boolean,"name": string,"organization_id": string,"therapeutic_class": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name": string,"organization_id": string,"therapeutic_class"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name"?: string,"organization_id"?: string,"therapeutic_class"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "generics_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"goods_receipt_items": {
                  Row: {
                    "batch_id": string,"batch_no": string,"bonus_quantity": number,"discount_paisa": number,"expiry_date": string,"goods_receipt_id": string,"id": string,"line_total_paisa": number,"medicine_id": string,"mrp_paisa": number,"organization_id": string,"quantity": number,"sale_price_paisa": number,"unit_cost_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id": string,"batch_no": string,"bonus_quantity"?: number,"discount_paisa"?: number,"expiry_date": string,"goods_receipt_id": string,"id"?: string,"line_total_paisa": number,"medicine_id": string,"mrp_paisa": number,"organization_id": string,"quantity": number,"sale_price_paisa": number,"unit_cost_paisa": number
                  }
                  Update: {
                    "batch_id"?: string,"batch_no"?: string,"bonus_quantity"?: number,"discount_paisa"?: number,"expiry_date"?: string,"goods_receipt_id"?: string,"id"?: string,"line_total_paisa"?: number,"medicine_id"?: string,"mrp_paisa"?: number,"organization_id"?: string,"quantity"?: number,"sale_price_paisa"?: number,"unit_cost_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "goods_receipt_items_organization_id_batch_id_fkey"
      columns: ["organization_id","batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "goods_receipt_items_organization_id_goods_receipt_id_fkey"
      columns: ["organization_id","goods_receipt_id"]
isOneToOne: false
      referencedRelation: "goods_receipts"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "goods_receipt_items_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"goods_receipts": {
                  Row: {
                    "branch_id": string,"business_date": string,"client_request_id": string,"created_at": string,"created_by": string,"discount_paisa": number,"id": string,"note": string | null,"organization_id": string,"paid_paisa": number,"receipt_no": string,"subtotal_paisa": number,"supplier_id": string,"supplier_invoice_date": string | null,"supplier_invoice_no": string | null,"total_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"business_date": string,"client_request_id": string,"created_at"?: string,"created_by": string,"discount_paisa"?: number,"id"?: string,"note"?: string | null,"organization_id": string,"paid_paisa"?: number,"receipt_no": string,"subtotal_paisa": number,"supplier_id": string,"supplier_invoice_date"?: string | null,"supplier_invoice_no"?: string | null,"total_paisa": number
                  }
                  Update: {
                    "branch_id"?: string,"business_date"?: string,"client_request_id"?: string,"created_at"?: string,"created_by"?: string,"discount_paisa"?: number,"id"?: string,"note"?: string | null,"organization_id"?: string,"paid_paisa"?: number,"receipt_no"?: string,"subtotal_paisa"?: number,"supplier_id"?: string,"supplier_invoice_date"?: string | null,"supplier_invoice_no"?: string | null,"total_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "goods_receipts_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "goods_receipts_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "supplier_balances"
      referencedColumns: ["organization_id","supplier_id"]
    },{
      foreignKeyName: "goods_receipts_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "suppliers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"inventory_movements": {
                  Row: {
                    "batch_id": string,"branch_id": string,"created_at": string,"created_by": string | null,"id": number,"medicine_id": string,"movement_type": Database["public"]['Enums']["movement_type"],"note": string | null,"organization_id": string,"quantity": number,"reference_id": string | null,"reference_type": string,"unit_cost_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id": string,"branch_id": string,"created_at"?: string,"created_by"?: string | null,"id"?: never,"medicine_id": string,"movement_type": Database["public"]['Enums']["movement_type"],"note"?: string | null,"organization_id": string,"quantity": number,"reference_id"?: string | null,"reference_type": string,"unit_cost_paisa": number
                  }
                  Update: {
                    "batch_id"?: string,"branch_id"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: never,"medicine_id"?: string,"movement_type"?: Database["public"]['Enums']["movement_type"],"note"?: string | null,"organization_id"?: string,"quantity"?: number,"reference_id"?: string | null,"reference_type"?: string,"unit_cost_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "inventory_movements_organization_id_batch_id_fkey"
      columns: ["organization_id","batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "inventory_movements_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "inventory_movements_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"invitations": {
                  Row: {
                    "accepted_at": string | null,"accepted_by": string | null,"branch_ids": (string)[],"created_at": string,"email": string,"expires_at": string,"id": string,"invited_by": string,"organization_id": string,"revoked_at": string | null,"role": Database["public"]['Enums']["org_role"]
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_at"?: string | null,"accepted_by"?: string | null,"branch_ids"?: (string)[],"created_at"?: string,"email": string,"expires_at"?: string,"id"?: string,"invited_by": string,"organization_id": string,"revoked_at"?: string | null,"role": Database["public"]['Enums']["org_role"]
                  }
                  Update: {
                    "accepted_at"?: string | null,"accepted_by"?: string | null,"branch_ids"?: (string)[],"created_at"?: string,"email"?: string,"expires_at"?: string,"id"?: string,"invited_by"?: string,"organization_id"?: string,"revoked_at"?: string | null,"role"?: Database["public"]['Enums']["org_role"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "invitations_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"loyalty_cards": {
                  Row: {
                    "card_no": string,"customer_id": string,"deactivated_at": string | null,"deactivation_reason": string | null,"id": string,"is_active": boolean,"issued_at": string,"issued_by": string | null,"organization_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "card_no": string,"customer_id": string,"deactivated_at"?: string | null,"deactivation_reason"?: string | null,"id"?: string,"is_active"?: boolean,"issued_at"?: string,"issued_by"?: string | null,"organization_id": string
                  }
                  Update: {
                    "card_no"?: string,"customer_id"?: string,"deactivated_at"?: string | null,"deactivation_reason"?: string | null,"id"?: string,"is_active"?: boolean,"issued_at"?: string,"issued_by"?: string | null,"organization_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "loyalty_cards_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customer_balances"
      referencedColumns: ["organization_id","customer_id"]
    },{
      foreignKeyName: "loyalty_cards_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"loyalty_memberships": {
                  Row: {
                    "branch_id": string,"cancel_reason": string | null,"cancelled_at": string | null,"cancelled_by": string | null,"card_id": string,"client_request_id": string,"created_at": string,"created_by": string,"customer_id": string,"discount_bp": number,"ends_on": string,"fee_paid_paisa": number,"id": string,"max_discount_per_invoice_paisa": number | null,"min_redeem_points": number,"organization_id": string,"payment_method": Database["public"]['Enums']["payment_method"] | null,"plan_id": string,"point_value_paisa": number,"points_per_100_taka": number,"renewed_from_id": string | null,"starts_on": string,"status": Database["public"]['Enums']["loyalty_membership_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"card_id": string,"client_request_id": string,"created_at"?: string,"created_by": string,"customer_id": string,"discount_bp": number,"ends_on": string,"fee_paid_paisa": number,"id"?: string,"max_discount_per_invoice_paisa"?: number | null,"min_redeem_points": number,"organization_id": string,"payment_method"?: Database["public"]['Enums']["payment_method"] | null,"plan_id": string,"point_value_paisa": number,"points_per_100_taka": number,"renewed_from_id"?: string | null,"starts_on": string,"status"?: Database["public"]['Enums']["loyalty_membership_status"]
                  }
                  Update: {
                    "branch_id"?: string,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"card_id"?: string,"client_request_id"?: string,"created_at"?: string,"created_by"?: string,"customer_id"?: string,"discount_bp"?: number,"ends_on"?: string,"fee_paid_paisa"?: number,"id"?: string,"max_discount_per_invoice_paisa"?: number | null,"min_redeem_points"?: number,"organization_id"?: string,"payment_method"?: Database["public"]['Enums']["payment_method"] | null,"plan_id"?: string,"point_value_paisa"?: number,"points_per_100_taka"?: number,"renewed_from_id"?: string | null,"starts_on"?: string,"status"?: Database["public"]['Enums']["loyalty_membership_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "loyalty_memberships_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_memberships_organization_id_card_id_fkey"
      columns: ["organization_id","card_id"]
isOneToOne: false
      referencedRelation: "loyalty_cards"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_memberships_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customer_balances"
      referencedColumns: ["organization_id","customer_id"]
    },{
      foreignKeyName: "loyalty_memberships_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customers"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_memberships_organization_id_plan_id_fkey"
      columns: ["organization_id","plan_id"]
isOneToOne: false
      referencedRelation: "loyalty_plans"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_memberships_renewed_from_id_fkey"
      columns: ["renewed_from_id"]
isOneToOne: false
      referencedRelation: "loyalty_memberships"
      referencedColumns: ["id"]
    }
                  ]
                },"loyalty_plans": {
                  Row: {
                    "created_at": string,"created_by": string | null,"discount_bp": number,"duration_months": number,"fee_paisa": number,"id": string,"is_active": boolean,"max_discount_per_invoice_paisa": number | null,"min_redeem_points": number,"name": string,"organization_id": string,"point_value_paisa": number,"points_per_100_taka": number,"sort_order": number,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"discount_bp"?: number,"duration_months": number,"fee_paisa"?: number,"id"?: string,"is_active"?: boolean,"max_discount_per_invoice_paisa"?: number | null,"min_redeem_points"?: number,"name": string,"organization_id": string,"point_value_paisa"?: number,"points_per_100_taka"?: number,"sort_order"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"discount_bp"?: number,"duration_months"?: number,"fee_paisa"?: number,"id"?: string,"is_active"?: boolean,"max_discount_per_invoice_paisa"?: number | null,"min_redeem_points"?: number,"name"?: string,"organization_id"?: string,"point_value_paisa"?: number,"points_per_100_taka"?: number,"sort_order"?: number,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "loyalty_plans_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"loyalty_point_ledger": {
                  Row: {
                    "branch_id": string | null,"card_id": string,"created_at": string,"created_by": string | null,"entry_type": string,"id": number,"note": string | null,"organization_id": string,"points": number,"sale_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id"?: string | null,"card_id": string,"created_at"?: string,"created_by"?: string | null,"entry_type": string,"id"?: never,"note"?: string | null,"organization_id": string,"points": number,"sale_id"?: string | null
                  }
                  Update: {
                    "branch_id"?: string | null,"card_id"?: string,"created_at"?: string,"created_by"?: string | null,"entry_type"?: string,"id"?: never,"note"?: string | null,"organization_id"?: string,"points"?: number,"sale_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "loyalty_point_ledger_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_point_ledger_organization_id_card_id_fkey"
      columns: ["organization_id","card_id"]
isOneToOne: false
      referencedRelation: "loyalty_cards"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "loyalty_point_ledger_organization_id_sale_id_fkey"
      columns: ["organization_id","sale_id"]
isOneToOne: false
      referencedRelation: "sales"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"manufacturers": {
                  Row: {
                    "country": string,"created_at": string,"created_by": string | null,"id": string,"is_active": boolean,"name": string,"organization_id": string,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "country"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name": string,"organization_id": string,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "country"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"name"?: string,"organization_id"?: string,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "manufacturers_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"medicine_barcodes": {
                  Row: {
                    "barcode": string,"created_at": string,"created_by": string | null,"id": string,"medicine_id": string,"organization_id": string,"pack_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "barcode": string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"medicine_id": string,"organization_id": string,"pack_id"?: string | null
                  }
                  Update: {
                    "barcode"?: string,"created_at"?: string,"created_by"?: string | null,"id"?: string,"medicine_id"?: string,"organization_id"?: string,"pack_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "medicine_barcodes_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "medicine_barcodes_organization_id_pack_id_fkey"
      columns: ["organization_id","pack_id"]
isOneToOne: false
      referencedRelation: "medicine_packs"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"medicine_packs": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"is_default": boolean,"medicine_id": string,"name": string,"organization_id": string,"units_per_pack": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_default"?: boolean,"medicine_id": string,"name": string,"organization_id": string,"units_per_pack": number
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_default"?: boolean,"medicine_id"?: string,"name"?: string,"organization_id"?: string,"units_per_pack"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "medicine_packs_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"medicines": {
                  Row: {
                    "base_unit_label": string,"brand_name": string,"created_at": string,"created_by": string | null,"dosage_form": Database["public"]['Enums']["dosage_form"],"generic_id": string | null,"id": string,"is_active": boolean,"loyalty_eligible": boolean,"manufacturer_id": string | null,"notes": string | null,"organization_id": string,"schedule": Database["public"]['Enums']["drug_schedule"],"sku": string | null,"strength": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "base_unit_label"?: string,"brand_name": string,"created_at"?: string,"created_by"?: string | null,"dosage_form": Database["public"]['Enums']["dosage_form"],"generic_id"?: string | null,"id"?: string,"is_active"?: boolean,"loyalty_eligible"?: boolean,"manufacturer_id"?: string | null,"notes"?: string | null,"organization_id": string,"schedule"?: Database["public"]['Enums']["drug_schedule"],"sku"?: string | null,"strength"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "base_unit_label"?: string,"brand_name"?: string,"created_at"?: string,"created_by"?: string | null,"dosage_form"?: Database["public"]['Enums']["dosage_form"],"generic_id"?: string | null,"id"?: string,"is_active"?: boolean,"loyalty_eligible"?: boolean,"manufacturer_id"?: string | null,"notes"?: string | null,"organization_id"?: string,"schedule"?: Database["public"]['Enums']["drug_schedule"],"sku"?: string | null,"strength"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "medicines_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "medicines_organization_id_generic_id_fkey"
      columns: ["organization_id","generic_id"]
isOneToOne: false
      referencedRelation: "generics"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "medicines_organization_id_manufacturer_id_fkey"
      columns: ["organization_id","manufacturer_id"]
isOneToOne: false
      referencedRelation: "manufacturers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"memberships": {
                  Row: {
                    "created_at": string,"created_by": string | null,"id": string,"is_active": boolean,"organization_id": string,"role": Database["public"]['Enums']["org_role"],"updated_at": string,"updated_by": string | null,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"organization_id": string,"role": Database["public"]['Enums']["org_role"],"updated_at"?: string,"updated_by"?: string | null,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"id"?: string,"is_active"?: boolean,"organization_id"?: string,"role"?: Database["public"]['Enums']["org_role"],"updated_at"?: string,"updated_by"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"opening_stock_loads": {
                  Row: {
                    "branch_id": string,"client_request_id": string,"created_at": string,"created_by": string,"id": string,"line_count": number,"organization_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"client_request_id": string,"created_at"?: string,"created_by": string,"id"?: string,"line_count": number,"organization_id": string
                  }
                  Update: {
                    "branch_id"?: string,"client_request_id"?: string,"created_at"?: string,"created_by"?: string,"id"?: string,"line_count"?: number,"organization_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "opening_stock_loads_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"organization_settings": {
                  Row: {
                    "ai_enabled": boolean,"cash_rounding": Database["public"]['Enums']["cash_rounding"],"enforce_mfa": boolean,"expiry_alert_days": number,"fiscal_year_start_month": number,"loyalty_enabled": boolean,"manager_max_discount_bp": number,"near_expiry_block_days": number,"organization_id": string,"require_prescription_for_rx": boolean,"return_window_days": number,"salesman_max_discount_bp": number,"updated_at": string,"updated_by": string | null,"vat_bp": number,"void_window_hours": number
                  }
                  ComputedFields: never
                  Insert: {
                    "ai_enabled"?: boolean,"cash_rounding"?: Database["public"]['Enums']["cash_rounding"],"enforce_mfa"?: boolean,"expiry_alert_days"?: number,"fiscal_year_start_month"?: number,"loyalty_enabled"?: boolean,"manager_max_discount_bp"?: number,"near_expiry_block_days"?: number,"organization_id": string,"require_prescription_for_rx"?: boolean,"return_window_days"?: number,"salesman_max_discount_bp"?: number,"updated_at"?: string,"updated_by"?: string | null,"vat_bp"?: number,"void_window_hours"?: number
                  }
                  Update: {
                    "ai_enabled"?: boolean,"cash_rounding"?: Database["public"]['Enums']["cash_rounding"],"enforce_mfa"?: boolean,"expiry_alert_days"?: number,"fiscal_year_start_month"?: number,"loyalty_enabled"?: boolean,"manager_max_discount_bp"?: number,"near_expiry_block_days"?: number,"organization_id"?: string,"require_prescription_for_rx"?: boolean,"return_window_days"?: number,"salesman_max_discount_bp"?: number,"updated_at"?: string,"updated_by"?: string | null,"vat_bp"?: number,"void_window_hours"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "organization_settings_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: true
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"organizations": {
                  Row: {
                    "created_at": string,"created_by": string | null,"currency": string,"id": string,"is_active": boolean,"name": string,"timezone": string,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"currency"?: string,"id"?: string,"is_active"?: boolean,"name": string,"timezone"?: string,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"currency"?: string,"id"?: string,"is_active"?: boolean,"name"?: string,"timezone"?: string,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"prescriptions": {
                  Row: {
                    "branch_id": string,"created_at": string,"created_by": string,"customer_id": string | null,"doctor_name": string,"doctor_reg_no": string | null,"id": string,"notes": string | null,"organization_id": string,"patient_age": number | null,"patient_name": string,"prescription_date": string,"storage_path": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"created_at"?: string,"created_by": string,"customer_id"?: string | null,"doctor_name": string,"doctor_reg_no"?: string | null,"id"?: string,"notes"?: string | null,"organization_id": string,"patient_age"?: number | null,"patient_name": string,"prescription_date": string,"storage_path"?: string | null
                  }
                  Update: {
                    "branch_id"?: string,"created_at"?: string,"created_by"?: string,"customer_id"?: string | null,"doctor_name"?: string,"doctor_reg_no"?: string | null,"id"?: string,"notes"?: string | null,"organization_id"?: string,"patient_age"?: number | null,"patient_name"?: string,"prescription_date"?: string,"storage_path"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "prescriptions_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "prescriptions_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customer_balances"
      referencedColumns: ["organization_id","customer_id"]
    },{
      foreignKeyName: "prescriptions_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"profiles": {
                  Row: {
                    "created_at": string,"full_name": string | null,"id": string,"phone": string | null,"preferred_language": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"full_name"?: string | null,"id": string,"phone"?: string | null,"preferred_language"?: string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"full_name"?: string | null,"id"?: string,"phone"?: string | null,"preferred_language"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"purchase_return_items": {
                  Row: {
                    "batch_id": string,"goods_receipt_item_id": string,"id": string,"line_total_paisa": number,"medicine_id": string,"organization_id": string,"purchase_return_id": string,"quantity": number,"unit_cost_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id": string,"goods_receipt_item_id": string,"id"?: string,"line_total_paisa": number,"medicine_id": string,"organization_id": string,"purchase_return_id": string,"quantity": number,"unit_cost_paisa": number
                  }
                  Update: {
                    "batch_id"?: string,"goods_receipt_item_id"?: string,"id"?: string,"line_total_paisa"?: number,"medicine_id"?: string,"organization_id"?: string,"purchase_return_id"?: string,"quantity"?: number,"unit_cost_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "purchase_return_items_organization_id_batch_id_fkey"
      columns: ["organization_id","batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "purchase_return_items_organization_id_goods_receipt_item_i_fkey"
      columns: ["organization_id","goods_receipt_item_id"]
isOneToOne: false
      referencedRelation: "goods_receipt_items"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "purchase_return_items_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "purchase_return_items_organization_id_purchase_return_id_fkey"
      columns: ["organization_id","purchase_return_id"]
isOneToOne: false
      referencedRelation: "purchase_returns"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"purchase_returns": {
                  Row: {
                    "branch_id": string,"business_date": string,"client_request_id": string,"created_at": string,"created_by": string,"id": string,"note": string | null,"organization_id": string,"reason": string,"return_no": string,"supplier_id": string,"total_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"business_date": string,"client_request_id": string,"created_at"?: string,"created_by": string,"id"?: string,"note"?: string | null,"organization_id": string,"reason": string,"return_no": string,"supplier_id": string,"total_paisa": number
                  }
                  Update: {
                    "branch_id"?: string,"business_date"?: string,"client_request_id"?: string,"created_at"?: string,"created_by"?: string,"id"?: string,"note"?: string | null,"organization_id"?: string,"reason"?: string,"return_no"?: string,"supplier_id"?: string,"total_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "purchase_returns_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "purchase_returns_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "supplier_balances"
      referencedColumns: ["organization_id","supplier_id"]
    },{
      foreignKeyName: "purchase_returns_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "suppliers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"sale_item_batches": {
                  Row: {
                    "batch_id": string,"id": string,"organization_id": string,"quantity": number,"returned_quantity": number,"sale_item_id": string,"unit_cost_paisa": number,"unit_price_paisa": number
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id": string,"id"?: string,"organization_id": string,"quantity": number,"returned_quantity"?: number,"sale_item_id": string,"unit_cost_paisa": number,"unit_price_paisa": number
                  }
                  Update: {
                    "batch_id"?: string,"id"?: string,"organization_id"?: string,"quantity"?: number,"returned_quantity"?: number,"sale_item_id"?: string,"unit_cost_paisa"?: number,"unit_price_paisa"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "sale_item_batches_organization_id_batch_id_fkey"
      columns: ["organization_id","batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sale_item_batches_organization_id_sale_item_id_fkey"
      columns: ["organization_id","sale_item_id"]
isOneToOne: false
      referencedRelation: "sale_items"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"sale_items": {
                  Row: {
                    "branch_id": string,"cost_paisa": number,"gross_paisa": number,"id": string,"invoice_discount_paisa": number,"line_discount_bp": number,"line_discount_paisa": number,"line_no": number,"loyalty_discount_paisa": number,"medicine_id": string,"net_paisa": number,"organization_id": string,"points_earned": number,"quantity": number,"returned_quantity": number,"rounding_paisa": number,"sale_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"cost_paisa": number,"gross_paisa": number,"id"?: string,"invoice_discount_paisa": number,"line_discount_bp"?: number,"line_discount_paisa": number,"line_no": number,"loyalty_discount_paisa": number,"medicine_id": string,"net_paisa": number,"organization_id": string,"points_earned"?: number,"quantity": number,"returned_quantity"?: number,"rounding_paisa"?: number,"sale_id": string
                  }
                  Update: {
                    "branch_id"?: string,"cost_paisa"?: number,"gross_paisa"?: number,"id"?: string,"invoice_discount_paisa"?: number,"line_discount_bp"?: number,"line_discount_paisa"?: number,"line_no"?: number,"loyalty_discount_paisa"?: number,"medicine_id"?: string,"net_paisa"?: number,"organization_id"?: string,"points_earned"?: number,"quantity"?: number,"returned_quantity"?: number,"rounding_paisa"?: number,"sale_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sale_items_organization_id_medicine_id_fkey"
      columns: ["organization_id","medicine_id"]
isOneToOne: false
      referencedRelation: "medicines"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sale_items_organization_id_sale_id_branch_id_fkey"
      columns: ["organization_id","sale_id","branch_id"]
isOneToOne: false
      referencedRelation: "sales"
      referencedColumns: ["organization_id","id","branch_id"]
    }
                  ]
                },"sale_payments": {
                  Row: {
                    "amount_paisa": number,"created_at": string,"id": string,"method": Database["public"]['Enums']["payment_method"],"organization_id": string,"reference": string | null,"sale_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paisa": number,"created_at"?: string,"id"?: string,"method": Database["public"]['Enums']["payment_method"],"organization_id": string,"reference"?: string | null,"sale_id": string
                  }
                  Update: {
                    "amount_paisa"?: number,"created_at"?: string,"id"?: string,"method"?: Database["public"]['Enums']["payment_method"],"organization_id"?: string,"reference"?: string | null,"sale_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sale_payments_organization_id_sale_id_fkey"
      columns: ["organization_id","sale_id"]
isOneToOne: false
      referencedRelation: "sales"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"sale_return_items": {
                  Row: {
                    "cost_paisa": number,"id": string,"organization_id": string,"quantity": number,"refund_paisa": number,"sale_item_id": string,"sale_return_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cost_paisa": number,"id"?: string,"organization_id": string,"quantity": number,"refund_paisa": number,"sale_item_id": string,"sale_return_id": string
                  }
                  Update: {
                    "cost_paisa"?: number,"id"?: string,"organization_id"?: string,"quantity"?: number,"refund_paisa"?: number,"sale_item_id"?: string,"sale_return_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sale_return_items_organization_id_sale_item_id_fkey"
      columns: ["organization_id","sale_item_id"]
isOneToOne: false
      referencedRelation: "sale_items"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sale_return_items_organization_id_sale_return_id_fkey"
      columns: ["organization_id","sale_return_id"]
isOneToOne: false
      referencedRelation: "sale_returns"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"sale_returns": {
                  Row: {
                    "branch_id": string,"business_date": string,"cash_refund_paisa": number,"client_request_id": string,"cost_paisa": number,"created_at": string,"created_by": string,"due_reduction_paisa": number,"id": string,"organization_id": string,"points_refund_value_paisa": number,"points_returned": number,"points_reversed": number,"points_shortfall_value_paisa": number,"reason": string,"refund_method": Database["public"]['Enums']["payment_method"] | null,"refund_paisa": number,"return_no": string,"sale_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"business_date": string,"cash_refund_paisa": number,"client_request_id": string,"cost_paisa": number,"created_at"?: string,"created_by": string,"due_reduction_paisa": number,"id"?: string,"organization_id": string,"points_refund_value_paisa"?: number,"points_returned"?: number,"points_reversed"?: number,"points_shortfall_value_paisa"?: number,"reason": string,"refund_method"?: Database["public"]['Enums']["payment_method"] | null,"refund_paisa": number,"return_no": string,"sale_id": string
                  }
                  Update: {
                    "branch_id"?: string,"business_date"?: string,"cash_refund_paisa"?: number,"client_request_id"?: string,"cost_paisa"?: number,"created_at"?: string,"created_by"?: string,"due_reduction_paisa"?: number,"id"?: string,"organization_id"?: string,"points_refund_value_paisa"?: number,"points_returned"?: number,"points_reversed"?: number,"points_shortfall_value_paisa"?: number,"reason"?: string,"refund_method"?: Database["public"]['Enums']["payment_method"] | null,"refund_paisa"?: number,"return_no"?: string,"sale_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sale_returns_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sale_returns_organization_id_sale_id_fkey"
      columns: ["organization_id","sale_id"]
isOneToOne: false
      referencedRelation: "sales"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"sales": {
                  Row: {
                    "branch_id": string,"business_date": string,"change_paisa": number,"client_request_id": string,"cost_paisa": number,"created_at": string,"created_by": string,"customer_id": string | null,"due_paisa": number,"gross_paisa": number,"id": string,"invoice_discount_paisa": number,"invoice_no": string,"line_discount_paisa": number,"loyalty_card_id": string | null,"loyalty_discount_paisa": number,"loyalty_membership_id": string | null,"net_paisa": number,"note": string | null,"organization_id": string,"paid_paisa": number,"points_earned": number,"points_redeemed": number,"points_redeemed_value_paisa": number,"prescription_id": string | null,"refunded_paisa": number,"rounding_paisa": number,"status": Database["public"]['Enums']["sale_status"],"total_paisa": number,"vat_included_paisa": number,"void_reason": string | null,"void_refund_method": Database["public"]['Enums']["payment_method"] | null,"void_refund_paisa": number,"voided_at": string | null,"voided_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id": string,"business_date": string,"change_paisa": number,"client_request_id": string,"cost_paisa": number,"created_at"?: string,"created_by": string,"customer_id"?: string | null,"due_paisa": number,"gross_paisa": number,"id"?: string,"invoice_discount_paisa": number,"invoice_no": string,"line_discount_paisa": number,"loyalty_card_id"?: string | null,"loyalty_discount_paisa": number,"loyalty_membership_id"?: string | null,"net_paisa": number,"note"?: string | null,"organization_id": string,"paid_paisa": number,"points_earned"?: number,"points_redeemed"?: number,"points_redeemed_value_paisa"?: number,"prescription_id"?: string | null,"refunded_paisa"?: number,"rounding_paisa"?: number,"status"?: Database["public"]['Enums']["sale_status"],"total_paisa": number,"vat_included_paisa"?: number,"void_reason"?: string | null,"void_refund_method"?: Database["public"]['Enums']["payment_method"] | null,"void_refund_paisa"?: number,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Update: {
                    "branch_id"?: string,"business_date"?: string,"change_paisa"?: number,"client_request_id"?: string,"cost_paisa"?: number,"created_at"?: string,"created_by"?: string,"customer_id"?: string | null,"due_paisa"?: number,"gross_paisa"?: number,"id"?: string,"invoice_discount_paisa"?: number,"invoice_no"?: string,"line_discount_paisa"?: number,"loyalty_card_id"?: string | null,"loyalty_discount_paisa"?: number,"loyalty_membership_id"?: string | null,"net_paisa"?: number,"note"?: string | null,"organization_id"?: string,"paid_paisa"?: number,"points_earned"?: number,"points_redeemed"?: number,"points_redeemed_value_paisa"?: number,"prescription_id"?: string | null,"refunded_paisa"?: number,"rounding_paisa"?: number,"status"?: Database["public"]['Enums']["sale_status"],"total_paisa"?: number,"vat_included_paisa"?: number,"void_reason"?: string | null,"void_refund_method"?: Database["public"]['Enums']["payment_method"] | null,"void_refund_paisa"?: number,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "sales_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sales_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customer_balances"
      referencedColumns: ["organization_id","customer_id"]
    },{
      foreignKeyName: "sales_organization_id_customer_id_fkey"
      columns: ["organization_id","customer_id"]
isOneToOne: false
      referencedRelation: "customers"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sales_organization_id_loyalty_card_id_fkey"
      columns: ["organization_id","loyalty_card_id"]
isOneToOne: false
      referencedRelation: "loyalty_cards"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sales_organization_id_loyalty_membership_id_fkey"
      columns: ["organization_id","loyalty_membership_id"]
isOneToOne: false
      referencedRelation: "loyalty_memberships"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "sales_organization_id_prescription_id_fkey"
      columns: ["organization_id","prescription_id"]
isOneToOne: false
      referencedRelation: "prescriptions"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"stock_adjustments": {
                  Row: {
                    "batch_id": string,"branch_id": string,"client_request_id": string,"created_at": string,"created_by": string,"id": string,"note": string | null,"organization_id": string,"quantity_delta": number,"reason": Database["public"]['Enums']["adjustment_reason"]
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id": string,"branch_id": string,"client_request_id": string,"created_at"?: string,"created_by": string,"id"?: string,"note"?: string | null,"organization_id": string,"quantity_delta": number,"reason": Database["public"]['Enums']["adjustment_reason"]
                  }
                  Update: {
                    "batch_id"?: string,"branch_id"?: string,"client_request_id"?: string,"created_at"?: string,"created_by"?: string,"id"?: string,"note"?: string | null,"organization_id"?: string,"quantity_delta"?: number,"reason"?: Database["public"]['Enums']["adjustment_reason"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_adjustments_organization_id_batch_id_fkey"
      columns: ["organization_id","batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "stock_adjustments_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"supplier_ledger_entries": {
                  Row: {
                    "amount_paisa": number,"branch_id": string | null,"created_at": string,"created_by": string | null,"entry_type": string,"id": number,"note": string | null,"organization_id": string,"reference_id": string | null,"reference_type": string | null,"supplier_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paisa": number,"branch_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"entry_type": string,"id"?: never,"note"?: string | null,"organization_id": string,"reference_id"?: string | null,"reference_type"?: string | null,"supplier_id": string
                  }
                  Update: {
                    "amount_paisa"?: number,"branch_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"entry_type"?: string,"id"?: never,"note"?: string | null,"organization_id"?: string,"reference_id"?: string | null,"reference_type"?: string | null,"supplier_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "supplier_ledger_entries_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "supplier_ledger_entries_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "supplier_balances"
      referencedColumns: ["organization_id","supplier_id"]
    },{
      foreignKeyName: "supplier_ledger_entries_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "suppliers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"supplier_payments": {
                  Row: {
                    "amount_paisa": number,"branch_id": string | null,"client_request_id": string | null,"created_by": string,"goods_receipt_id": string | null,"id": string,"method": Database["public"]['Enums']["payment_method"],"note": string | null,"organization_id": string,"paid_at": string,"reference": string | null,"supplier_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_paisa": number,"branch_id"?: string | null,"client_request_id"?: string | null,"created_by": string,"goods_receipt_id"?: string | null,"id"?: string,"method": Database["public"]['Enums']["payment_method"],"note"?: string | null,"organization_id": string,"paid_at"?: string,"reference"?: string | null,"supplier_id": string
                  }
                  Update: {
                    "amount_paisa"?: number,"branch_id"?: string | null,"client_request_id"?: string | null,"created_by"?: string,"goods_receipt_id"?: string | null,"id"?: string,"method"?: Database["public"]['Enums']["payment_method"],"note"?: string | null,"organization_id"?: string,"paid_at"?: string,"reference"?: string | null,"supplier_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "supplier_payments_organization_id_branch_id_fkey"
      columns: ["organization_id","branch_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "supplier_payments_organization_id_goods_receipt_id_fkey"
      columns: ["organization_id","goods_receipt_id"]
isOneToOne: false
      referencedRelation: "goods_receipts"
      referencedColumns: ["organization_id","id"]
    },{
      foreignKeyName: "supplier_payments_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "supplier_balances"
      referencedColumns: ["organization_id","supplier_id"]
    },{
      foreignKeyName: "supplier_payments_organization_id_supplier_id_fkey"
      columns: ["organization_id","supplier_id"]
isOneToOne: false
      referencedRelation: "suppliers"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"suppliers": {
                  Row: {
                    "address": string | null,"contact_person": string | null,"created_at": string,"created_by": string | null,"email": string | null,"id": string,"is_active": boolean,"name": string,"notes": string | null,"organization_id": string,"phone": string | null,"updated_at": string,"updated_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"contact_person"?: string | null,"created_at"?: string,"created_by"?: string | null,"email"?: string | null,"id"?: string,"is_active"?: boolean,"name": string,"notes"?: string | null,"organization_id": string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Update: {
                    "address"?: string | null,"contact_person"?: string | null,"created_at"?: string,"created_by"?: string | null,"email"?: string | null,"id"?: string,"is_active"?: boolean,"name"?: string,"notes"?: string | null,"organization_id"?: string,"phone"?: string | null,"updated_at"?: string,"updated_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "suppliers_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            "customer_balances": {
                  Row: {
                    "balance_paisa": number | null,"credit_limit_paisa": number | null,"customer_id": string | null,"name": string | null,"organization_id": string | null,"phone": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "customers_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                },"loyalty_usage_daily": {
                  Row: {
                    "branches_count": number | null,"business_date": string | null,"loyalty_card_id": string | null,"loyalty_discount_paisa": number | null,"organization_id": string | null,"sales_count": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "sales_organization_id_loyalty_card_id_fkey"
      columns: ["organization_id","loyalty_card_id"]
isOneToOne: false
      referencedRelation: "loyalty_cards"
      referencedColumns: ["organization_id","id"]
    }
                  ]
                },"supplier_balances": {
                  Row: {
                    "balance_paisa": number | null,"name": string | null,"organization_id": string | null,"supplier_id": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "suppliers_organization_id_fkey"
      columns: ["organization_id"]
isOneToOne: false
      referencedRelation: "organizations"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "accept_invitation":
{ Args: { "p_invitation_id": string }; Returns: string
                           },
"add_member":
{ Args: { "p_branch_ids"?: (string)[],"p_email": string,"p_organization_id": string,"p_role": Database["public"]['Enums']["org_role"] }; Returns: string
                           },
"add_opening_stock":
{ Args: { "p_branch_id": string,"p_client_request_id": string,"p_items": Json }; Returns: number
                           },
"adjust_stock":
{ Args: { "p_batch_id": string,"p_client_request_id": string,"p_note"?: string,"p_quantity_delta": number,"p_reason": Database["public"]['Enums']["adjustment_reason"] }; Returns: string
                           },
"cancel_loyalty_membership":
{ Args: { "p_membership_id": string,"p_reason": string }; Returns: undefined
                           },
"create_branch":
{ Args: { "p_address"?: string,"p_code": string,"p_name": string,"p_organization_id": string,"p_phone"?: string }; Returns: string
                           },
"create_organization":
{ Args: { "p_branch_code": string,"p_branch_name": string,"p_name": string,"p_timezone"?: string }; Returns: string
                           },
"create_sale":
{ Args: { "p_branch_id": string,"p_client_request_id": string,"p_customer_id"?: string,"p_invoice_discount_paisa"?: number,"p_items": Json,"p_loyalty_card_no"?: string,"p_note"?: string,"p_payments": Json,"p_prescription"?: Json }; Returns: Json
                           },
"enroll_loyalty":
{ Args: { "p_branch_id": string,"p_card_no"?: string,"p_client_request_id": string,"p_customer_id": string,"p_payment_method"?: Database["public"]['Enums']["payment_method"],"p_plan_id": string }; Returns: Json
                           },
"leave_organization":
{ Args: { "p_organization_id": string }; Returns: undefined
                           },
"lookup_loyalty":
{ Args: { "p_card_or_phone": string,"p_organization_id": string }; Returns: {
              "card_id": string,"card_no": string,"customer_id": string,"customer_name": string,"discount_bp": number,"ends_on": string,"membership_id": string,"plan_name": string,"points_balance": number,"starts_on": string
            }[]
                           },
"my_invitations":
{ Args: Record<PropertyKey, never>; Returns: {
              "expires_at": string,"invitation_id": string,"organization_id": string,"organization_name": string,"role": Database["public"]['Enums']["org_role"]
            }[]
                           },
"process_purchase_return":
{ Args: { "p_branch_id": string,"p_client_request_id": string,"p_items": Json,"p_note"?: string,"p_reason": string,"p_supplier_id": string }; Returns: Json
                           },
"process_sale_return":
{ Args: { "p_client_request_id": string,"p_items": Json,"p_reason": string,"p_refund_method"?: Database["public"]['Enums']["payment_method"],"p_sale_id": string }; Returns: Json
                           },
"quote_sale":
{ Args: { "p_branch_id": string,"p_customer_id"?: string,"p_invoice_discount_paisa"?: number,"p_items": Json,"p_loyalty_card_no"?: string,"p_prescription"?: Json }; Returns: Json
                           },
"receive_goods":
{ Args: { "p_branch_id": string,"p_client_request_id": string,"p_discount_paisa"?: number,"p_items": Json,"p_note"?: string,"p_paid_paisa"?: number,"p_payment_method"?: Database["public"]['Enums']["payment_method"],"p_supplier_id": string,"p_supplier_invoice_date"?: string,"p_supplier_invoice_no"?: string }; Returns: Json
                           },
"record_customer_payment":
{ Args: { "p_amount_paisa": number,"p_branch_id": string,"p_client_request_id": string,"p_customer_id": string,"p_method": Database["public"]['Enums']["payment_method"],"p_reference"?: string }; Returns: number
                           },
"record_supplier_payment":
{ Args: { "p_amount_paisa": number,"p_branch_id"?: string,"p_client_request_id": string,"p_method": Database["public"]['Enums']["payment_method"],"p_note"?: string,"p_reference"?: string,"p_supplier_id": string }; Returns: string
                           },
"replace_loyalty_card":
{ Args: { "p_card_id": string,"p_new_card_no"?: string,"p_reason": string }; Returns: string
                           },
"report_expiring_stock":
{ Args: { "p_branch_id": string,"p_days"?: number }; Returns: {
              "batch_id": string,"batch_no": string,"brand_name": string,"days_left": number,"expiry_date": string,"medicine_id": string,"quantity_on_hand": number,"stock_value_cost_paisa": number,"stock_value_mrp_paisa": number
            }[]
                           },
"report_low_stock":
{ Args: { "p_branch_id": string }; Returns: {
              "brand_name": string,"generic_name": string,"medicine_id": string,"rack_location": string,"reorder_level": number,"sellable_quantity": number
            }[]
                           },
"report_sales_summary":
{ Args: { "p_branch_id"?: string,"p_from": string,"p_organization_id": string,"p_to": string }; Returns: {
              "branch_id": string,"branch_name": string,"business_date": string,"cost_paisa": number,"credit_sales_paisa": number,"discount_paisa": number,"gross_paisa": number,"gross_profit_paisa": number,"loyalty_discount_paisa": number,"net_sales_paisa": number,"returns_paisa": number,"sales_count": number,"voided_paisa": number
            }[]
                           },
"report_stock_value":
{ Args: { "p_organization_id": string }; Returns: {
              "branch_id": string,"branch_name": string,"expired_units": number,"sku_count": number,"units": number,"value_cost_paisa": number,"value_mrp_paisa": number
            }[]
                           },
"save_medicine":
{ Args: { "p_barcodes"?: (string)[],"p_base_unit_label"?: string,"p_branch_id"?: string,"p_brand_name": string,"p_dosage_form": Database["public"]['Enums']["dosage_form"],"p_generic_name"?: string,"p_is_active"?: boolean,"p_loyalty_eligible"?: boolean,"p_manufacturer_name"?: string,"p_medicine_id"?: string,"p_notes"?: string,"p_organization_id": string,"p_rack_location"?: string,"p_reorder_level"?: number,"p_schedule"?: Database["public"]['Enums']["drug_schedule"],"p_sku"?: string,"p_strength"?: string }; Returns: string
                           },
"search_medicines":
{ Args: { "p_branch_id": string,"p_limit"?: number,"p_query": string }; Returns: {
              "base_unit_label": string,"brand_name": string,"dosage_form": Database["public"]['Enums']["dosage_form"],"generic_name": string,"manufacturer_name": string,"medicine_id": string,"nearest_expiry": string,"rack_location": string,"sale_price_paisa": number,"schedule": Database["public"]['Enums']["drug_schedule"],"stock_quantity": number,"strength": string
            }[]
                           },
"set_batch_price":
{ Args: { "p_batch_id": string,"p_mrp_paisa"?: number,"p_sale_price_paisa": number }; Returns: undefined
                           },
"set_customer_credit_limit":
{ Args: { "p_credit_limit_paisa": number,"p_customer_id": string }; Returns: undefined
                           },
"update_member":
{ Args: { "p_branch_ids": (string)[],"p_is_active": boolean,"p_membership_id": string,"p_role": Database["public"]['Enums']["org_role"] }; Returns: undefined
                           },
"void_sale":
{ Args: { "p_reason": string,"p_refund_method"?: Database["public"]['Enums']["payment_method"],"p_sale_id": string }; Returns: Json
                           }
          }
          Enums: {
            "adjustment_reason": "damage"|"loss"|"theft"|"count_correction"|"expired_writeoff"|"opening_balance"|"other","cash_rounding": "none"|"nearest_taka","dosage_form": "tablet"|"capsule"|"syrup"|"suspension"|"solution"|"injection"|"infusion"|"drops"|"cream"|"ointment"|"gel"|"lotion"|"inhaler"|"nebuliser_solution"|"powder"|"sachet"|"suppository"|"spray"|"patch"|"device"|"other","drug_schedule": "otc"|"rx"|"controlled","loyalty_membership_status": "active"|"cancelled","movement_type": "purchase_receipt"|"sale"|"sale_void"|"sale_return"|"purchase_return"|"transfer_out"|"transfer_in"|"adjustment"|"expiry_writeoff"|"count_correction"|"opening_balance","org_role": "owner"|"manager"|"salesman"|"accountant"|"auditor","payment_method": "cash"|"bkash"|"nagad"|"rocket"|"card"|"bank_transfer"|"loyalty_points","sale_status": "completed"|"voided"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "adjustment_reason": ["damage", "loss", "theft", "count_correction", "expired_writeoff", "opening_balance", "other"],"cash_rounding": ["none", "nearest_taka"],"dosage_form": ["tablet", "capsule", "syrup", "suspension", "solution", "injection", "infusion", "drops", "cream", "ointment", "gel", "lotion", "inhaler", "nebuliser_solution", "powder", "sachet", "suppository", "spray", "patch", "device", "other"],"drug_schedule": ["otc", "rx", "controlled"],"loyalty_membership_status": ["active", "cancelled"],"movement_type": ["purchase_receipt", "sale", "sale_void", "sale_return", "purchase_return", "transfer_out", "transfer_in", "adjustment", "expiry_writeoff", "count_correction", "opening_balance"],"org_role": ["owner", "manager", "salesman", "accountant", "auditor"],"payment_method": ["cash", "bkash", "nagad", "rocket", "card", "bank_transfer", "loyalty_points"],"sale_status": ["completed", "voided"]
          }
        }
} as const
