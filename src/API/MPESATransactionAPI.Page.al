page 50102 "MPESA Transaction API"
{
    // Called by the callback relay (Azure Function / Logic App) with an Entra ID
    // service-to-service token. Daraja cannot authenticate to Business Central
    // directly, so the relay receives its callbacks and forwards them here.
    //
    //  POST  .../api/mtende/mpesa/v1.0/companies({id})/mpesaTransactions
    //        -> registers a C2B (PayBill) confirmation
    //  POST  .../mpesaTransactions({systemId})/Microsoft.NAV.completeStkPush
    //        -> records the result of an STK Push request
    PageType = API;
    APIPublisher = 'mtende';
    APIGroup = 'mpesa';
    APIVersion = 'v1.0';
    EntityName = 'mpesaTransaction';
    EntitySetName = 'mpesaTransactions';
    EntityCaption = 'M-Pesa Transaction';
    EntitySetCaption = 'M-Pesa Transactions';
    SourceTable = "MPESA Transaction";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    DeleteAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Records)
            {
                field(id; Rec.SystemId) { Caption = 'Id'; Editable = false; }
                field(entryNo; Rec."Entry No.") { Caption = 'Entry No.'; Editable = false; }
                field(transactionType; Rec."Transaction Type") { Caption = 'Transaction Type'; Editable = false; }
                field(status; Rec.Status) { Caption = 'Status'; Editable = false; }
                field(phoneNo; Rec."Phone No.") { Caption = 'Phone No.'; }
                field(amount; Rec.Amount) { Caption = 'Amount'; }
                field(accountReference; Rec."Account Reference") { Caption = 'Account Reference'; }
                field(receiptNo; Rec."M-Pesa Receipt No.") { Caption = 'M-Pesa Receipt No.'; }
                field(transactionDate; Rec."Transaction Date") { Caption = 'Transaction Date'; }
                field(payerName; Rec."Payer Name") { Caption = 'Payer Name'; }
                field(checkoutRequestId; Rec."Checkout Request ID") { Caption = 'Checkout Request ID'; Editable = false; }
                field(customerNo; Rec."Customer No.") { Caption = 'Customer No.'; Editable = false; }
                field(documentNo; Rec."Document No.") { Caption = 'Applies-to Invoice No.'; Editable = false; }
                field(resultCode; Rec."Result Code") { Caption = 'Result Code'; Editable = false; }
                field(resultDescription; Rec."Result Description") { Caption = 'Result Description'; Editable = false; }
                field(postedDocumentNo; Rec."Posted Document No.") { Caption = 'Posted Document No.'; Editable = false; }
                field(errorMessage; Rec."Error Message") { Caption = 'Error Message'; Editable = false; }
            }
        }
    }

    var
        MpesaApiMgt: Codeunit "MPESA API Mgt.";
        ReadOnlyErr: Label 'M-Pesa transactions cannot be changed through PATCH. Use the completeStkPush action.';

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    begin
        MpesaApiMgt.RegisterC2BConfirmation(Rec);
        exit(true);
    end;

    trigger OnModifyRecord(): Boolean
    begin
        // Records change only through the bound action, never by PATCH.
        Error(ReadOnlyErr);
    end;

    [ServiceEnabled]
    procedure completeStkPush(var ActionContext: WebServiceActionContext; resultCode: Integer; resultDescription: Text; receiptNo: Text; transactionDate: Text)
    begin
        MpesaApiMgt.CompleteStkPush(Rec, resultCode, resultDescription, receiptNo, transactionDate);

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"MPESA Transaction API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;
}
