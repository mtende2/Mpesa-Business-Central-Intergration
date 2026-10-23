page 50101 "MPESA Transactions"
{
    Caption = 'M-Pesa Transactions';
    PageType = List;
    SourceTable = "MPESA Transaction";
    SourceTableView = sorting("Entry No.") order(descending);
    ApplicationArea = All;
    UsageCategory = Lists;
    InsertAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Entry No."; Rec."Entry No.") { Editable = false; ToolTip = 'Specifies the entry number.'; }
                field("Transaction Type"; Rec."Transaction Type") { Editable = false; ToolTip = 'Specifies whether the payment came from an STK Push request or a direct PayBill (C2B) payment.'; }
                field(Status; Rec.Status) { Editable = false; StyleExpr = StatusStyle; ToolTip = 'Specifies the processing status.'; }
                field("Transaction Date"; Rec."Transaction Date") { Editable = false; ToolTip = 'Specifies when M-Pesa completed the payment.'; }
                field("M-Pesa Receipt No."; Rec."M-Pesa Receipt No.") { Editable = false; ToolTip = 'Specifies the Safaricom receipt number.'; }
                field(Amount; Rec.Amount) { Editable = false; ToolTip = 'Specifies the amount paid.'; }
                field("Phone No."; Rec."Phone No.") { Editable = false; ToolTip = 'Specifies the payer phone number.'; }
                field("Payer Name"; Rec."Payer Name") { Editable = false; ToolTip = 'Specifies the payer name reported by M-Pesa.'; }
                field("Account Reference"; Rec."Account Reference") { Editable = false; ToolTip = 'Specifies the account reference entered by the payer.'; }
                field("Customer No."; Rec."Customer No.") { ToolTip = 'Specifies the matched customer. Assign one manually to release an unmatched payment for posting.'; }
                field("Customer Name"; Rec."Customer Name") { ToolTip = 'Specifies the customer name.'; }
                field("Document No."; Rec."Document No.") { ToolTip = 'Specifies the posted sales invoice the payment is applied to.'; }
                field("Posted Document No."; Rec."Posted Document No.") { ToolTip = 'Specifies the posted payment document number.'; }
                field("Result Description"; Rec."Result Description") { Editable = false; ToolTip = 'Specifies the result reported by Daraja.'; }
                field("Error Message"; Rec."Error Message") { ToolTip = 'Specifies the last posting error.'; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PostPayment)
            {
                Caption = 'Post Payment';
                Image = Post;
                ToolTip = 'Posts the selected payment as a customer payment, applied to its invoice if one is linked.';
                trigger OnAction()
                var
                    MpesaPostingMgt: Codeunit "MPESA Posting Mgt.";
                begin
                    MpesaPostingMgt.PostTransaction(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(Retry)
            {
                Caption = 'Reset Error';
                Image = ResetStatus;
                ToolTip = 'Clears the posting error so the job queue tries the payment again.';
                trigger OnAction()
                begin
                    Rec.TestField(Status, Rec.Status::Error);
                    Rec.Status := Rec.Status::Completed;
                    Rec."Error Message" := '';
                    Rec.Modify(true);
                end;
            }
        }
        area(Navigation)
        {
            action(CustomerLedger)
            {
                Caption = 'Customer Ledger Entries';
                Image = CustomerLedger;
                RunObject = page "Customer Ledger Entries";
                RunPageLink = "Customer No." = field("Customer No."), "Document No." = field("Posted Document No.");
                ToolTip = 'Shows the ledger entry created when the payment was posted.';
            }
        }
        area(Promoted)
        {
            actionref(PostPayment_Promoted; PostPayment) { }
            actionref(Retry_Promoted; Retry) { }
        }
    }

    var
        StatusStyle: Text;

    trigger OnAfterGetRecord()
    begin
        case Rec.Status of
            Rec.Status::Posted:
                StatusStyle := 'Favorable';
            Rec.Status::Failed, Rec.Status::Error:
                StatusStyle := 'Unfavorable';
            Rec.Status::Unmatched:
                StatusStyle := 'Ambiguous';
            else
                StatusStyle := 'Standard';
        end;
    end;
}
