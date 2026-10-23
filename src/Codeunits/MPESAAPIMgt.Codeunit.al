codeunit 50100 "MPESA API Mgt."
{
    Access = Public;

    var

        Base64Convert: Codeunit "Base64 Convert";
        TokenCacheLbl: Label 'MPESA-AccessToken', Locked = true;
        TokenExpiryLbl: Label 'MPESA-AccessTokenExpiry', Locked = true;
        PasswordPlaceholderTxt: Label '#MPESA-PASSWORD#', Locked = true;
        InvalidPhoneErr: Label '%1 is not a valid Safaricom mobile number. Use the format 07XXXXXXXX, 01XXXXXXXX or 2547XXXXXXXX.', Comment = '%1 = phone number';
        InvalidAmountErr: Label 'The amount must be at least KES 1.';
        DarajaErr: Label 'M-Pesa returned an error (HTTP %1): %2', Comment = '%1 = status code, %2 = message';
        StkRejectedErr: Label 'M-Pesa rejected the payment request: %1', Comment = '%1 = response description';
        ConnectionOkMsg: Label 'Connected to the M-Pesa %1 API successfully.', Comment = '%1 = environment';
        NotStkErr: Label 'Entry %1 is not an STK Push transaction.', Comment = '%1 = entry no.';
        TokenMissingErr: Label 'Daraja did not return an access token.';

    // ---------------------------------------------------------------
    // STK Push (Lipa Na M-Pesa Online)
    // ---------------------------------------------------------------

    procedure InitiateStkPush(PhoneNo: Text; Amount: Decimal; AccountReference: Code[20]; CustomerNo: Code[20]; DocumentNo: Code[20]): Integer
    var
        Setup: Record "MPESA Setup";
        MpesaTransaction: Record "MPESA Transaction";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        Body: SecretText;
        BodyText: Text;
        Timestamp: Text;
        NormalizedPhone: Text;
        RoundedAmount: Decimal;
        PlaceholderPos: Integer;
    begin
        Setup.Get();
        Setup.TestSetupForStkPush();

        NormalizedPhone := NormalizePhoneNo(PhoneNo);
        RoundedAmount := Round(Amount, 1, '>');
        if RoundedAmount < 1 then
            Error(InvalidAmountErr);

        Timestamp := GetTimestamp();

        RequestJson.Add('BusinessShortCode', Setup."Business Short Code");
        RequestJson.Add('Password', PasswordPlaceholderTxt);
        RequestJson.Add('Timestamp', Timestamp);
        RequestJson.Add('TransactionType', 'CustomerPayBillOnline');
        RequestJson.Add('Amount', RoundedAmount);
        RequestJson.Add('PartyA', NormalizedPhone);
        RequestJson.Add('PartyB', Setup."Business Short Code");
        RequestJson.Add('PhoneNumber', NormalizedPhone);
        RequestJson.Add('CallBackURL', Setup."Callback URL");
        RequestJson.Add('AccountReference', CopyStr(AccountReference, 1, 12));
        RequestJson.Add('TransactionDesc', CopyStr(StrSubstNo('Payment %1', AccountReference), 1, 13));
        RequestJson.WriteTo(BodyText);

        // The password is derived from the passkey, so it is injected as SecretText
        // and never exists as plain Text inside Business Central.
        PlaceholderPos := StrPos(BodyText, PasswordPlaceholderTxt);
        Body := SecretStrSubstNo('%1%2%3',
            CopyStr(BodyText, 1, PlaceholderPos - 1),
            BuildPassword(Setup."Business Short Code", Setup.GetPasskey(), Timestamp),
            CopyStr(BodyText, PlaceholderPos + StrLen(PasswordPlaceholderTxt)));

        SendRequest(Setup, 'POST', '/mpesa/stkpush/v1/processrequest', Body, ResponseJson);

        if GetJsonText(ResponseJson, 'ResponseCode') <> '0' then
            Error(StkRejectedErr, GetJsonText(ResponseJson, 'ResponseDescription'));

        MpesaTransaction.Init();
        MpesaTransaction."Transaction Type" := MpesaTransaction."Transaction Type"::"STK Push";
        MpesaTransaction.Status := MpesaTransaction.Status::Pending;
        MpesaTransaction."Phone No." := CopyStr(NormalizedPhone, 1, MaxStrLen(MpesaTransaction."Phone No."));
        MpesaTransaction.Amount := RoundedAmount;
        MpesaTransaction."Account Reference" := AccountReference;
        MpesaTransaction."Customer No." := CustomerNo;
        MpesaTransaction."Document No." := DocumentNo;
        MpesaTransaction."Merchant Request ID" := CopyStr(GetJsonText(ResponseJson, 'MerchantRequestID'), 1, MaxStrLen(MpesaTransaction."Merchant Request ID"));
        MpesaTransaction."Checkout Request ID" := CopyStr(GetJsonText(ResponseJson, 'CheckoutRequestID'), 1, MaxStrLen(MpesaTransaction."Checkout Request ID"));
        MpesaTransaction."Result Description" := CopyStr(GetJsonText(ResponseJson, 'CustomerMessage'), 1, MaxStrLen(MpesaTransaction."Result Description"));
        MpesaTransaction.Insert(true);

        OnAfterStkPushInitiated(MpesaTransaction);
        exit(MpesaTransaction."Entry No.");
    end;

    // ---------------------------------------------------------------
    // Callbacks (called from the API page by the callback relay)
    // ---------------------------------------------------------------

    procedure CompleteStkPush(var MpesaTransaction: Record "MPESA Transaction"; ResultCode: Integer; ResultDescription: Text; ReceiptNo: Text; TransactionDateText: Text)
    begin
        if MpesaTransaction."Transaction Type" <> MpesaTransaction."Transaction Type"::"STK Push" then
            Error(NotStkErr, MpesaTransaction."Entry No.");

        // Daraja may deliver the same callback more than once; ignore repeats.
        if MpesaTransaction.Status <> MpesaTransaction.Status::Pending then
            exit;

        MpesaTransaction."Result Code" := ResultCode;
        MpesaTransaction."Result Description" := CopyStr(ResultDescription, 1, MaxStrLen(MpesaTransaction."Result Description"));

        if ResultCode = 0 then begin
            MpesaTransaction."M-Pesa Receipt No." := CopyStr(ReceiptNo, 1, MaxStrLen(MpesaTransaction."M-Pesa Receipt No."));
            MpesaTransaction.CheckDuplicateReceipt();
            MpesaTransaction."Transaction Date" := ParseDarajaDateTime(TransactionDateText);
            if MpesaTransaction."Customer No." = '' then
                MpesaTransaction.Status := MpesaTransaction.Status::Unmatched
            else
                MpesaTransaction.Status := MpesaTransaction.Status::Completed;
        end else
            MpesaTransaction.Status := MpesaTransaction.Status::Failed;

        MpesaTransaction.Modify(true);
        OnAfterStkPushCompleted(MpesaTransaction);
    end;

    procedure RegisterC2BConfirmation(var MpesaTransaction: Record "MPESA Transaction")
    begin
        MpesaTransaction.TestField("M-Pesa Receipt No.");
        MpesaTransaction.TestField(Amount);
        MpesaTransaction.CheckDuplicateReceipt();

        MpesaTransaction."Transaction Type" := MpesaTransaction."Transaction Type"::C2B;
        if MpesaTransaction."Transaction Date" = 0DT then
            MpesaTransaction."Transaction Date" := CurrentDateTime();

        ResolveAccountReference(MpesaTransaction);

        if MpesaTransaction."Customer No." = '' then
            MpesaTransaction.Status := MpesaTransaction.Status::Unmatched
        else
            MpesaTransaction.Status := MpesaTransaction.Status::Completed;

        OnAfterC2BRegistered(MpesaTransaction);
    end;

    procedure ResolveAccountReference(var MpesaTransaction: Record "MPESA Transaction")
    var
        Customer: Record Customer;
        SalesInvoiceHeader: Record "Sales Invoice Header";
        IsHandled: Boolean;
    begin
        OnBeforeResolveAccountReference(MpesaTransaction, IsHandled);
        if IsHandled then
            exit;

        if MpesaTransaction."Account Reference" = '' then
            exit;

        // 1. Payer typed an invoice number: apply to that invoice.
        if SalesInvoiceHeader.Get(MpesaTransaction."Account Reference") then begin
            MpesaTransaction."Customer No." := SalesInvoiceHeader."Bill-to Customer No.";
            MpesaTransaction."Document No." := SalesInvoiceHeader."No.";
            exit;
        end;

        // 2. Payer typed a customer number: post on account.
        if Customer.Get(MpesaTransaction."Account Reference") then
            MpesaTransaction."Customer No." := Customer."No.";
    end;

    // ---------------------------------------------------------------
    // Authentication
    // ---------------------------------------------------------------

    procedure TestConnection()
    var
        Setup: Record "MPESA Setup";
    begin
        Setup.Get();
        ClearTokenCache();
        GetAccessToken(Setup);
        Message(ConnectionOkMsg, Setup.Environment);
    end;

    local procedure GetAccessToken(Setup: Record "MPESA Setup") AccessToken: SecretText
    var
        Client: HttpClient;
        Request: HttpRequestMessage;
        Response: HttpResponseMessage;
        Headers: HttpHeaders;
        ResponseJson: JsonObject;
        ResponseText: Text;
        TokenText: Text;
        ExpiresInSeconds: Integer;
    begin
        if TryGetCachedToken(AccessToken) then
            exit(AccessToken);

        Request.Method('GET');
        Request.SetRequestUri(Setup.GetBaseUrl() + '/oauth/v1/generate?grant_type=client_credentials');
        Request.GetHeaders(Headers);
        Headers.Add('Authorization',
            SecretStrSubstNo('Basic %1',
                Base64Convert.ToBase64(SecretStrSubstNo('%1:%2', Setup.GetConsumerKey(), Setup.GetConsumerSecret()))));

        Client.Send(Request, Response);
        Response.Content.ReadAs(ResponseText);
        if not Response.IsSuccessStatusCode() then
            Error(DarajaErr, Response.HttpStatusCode(), ResponseText);

        ResponseJson.ReadFrom(ResponseText);
        TokenText := GetJsonText(ResponseJson, 'access_token');
        if TokenText = '' then
            Error(TokenMissingErr);
        if not Evaluate(ExpiresInSeconds, GetJsonText(ResponseJson, 'expires_in')) then
            ExpiresInSeconds := 3599;

        AccessToken := TokenText;
        CacheToken(AccessToken, ExpiresInSeconds);
    end;

    local procedure TryGetCachedToken(var AccessToken: SecretText): Boolean
    var
        ExpiryText: Text;
        Expiry: DateTime;
    begin
        if not IsolatedStorage.Get(TokenExpiryLbl, DataScope::Company, ExpiryText) then
            exit(false);
        if not Evaluate(Expiry, ExpiryText, 9) then
            exit(false);
        if CurrentDateTime() >= Expiry then
            exit(false);
        exit(IsolatedStorage.Get(TokenCacheLbl, DataScope::Company, AccessToken));
    end;

    local procedure CacheToken(AccessToken: SecretText; ExpiresInSeconds: Integer)
    var
        Expiry: DateTime;
    begin
        // Refresh one minute early to avoid using a token that expires mid-request.
        Expiry := CurrentDateTime() + ((ExpiresInSeconds - 60) * 1000);
        IsolatedStorage.Set(TokenCacheLbl, AccessToken, DataScope::Company);
        IsolatedStorage.Set(TokenExpiryLbl, Format(Expiry, 0, 9), DataScope::Company);
    end;

    local procedure ClearTokenCache()
    begin
        if IsolatedStorage.Contains(TokenCacheLbl, DataScope::Company) then
            IsolatedStorage.Delete(TokenCacheLbl, DataScope::Company);
        if IsolatedStorage.Contains(TokenExpiryLbl, DataScope::Company) then
            IsolatedStorage.Delete(TokenExpiryLbl, DataScope::Company);
    end;

    // ---------------------------------------------------------------
    // HTTP and helpers
    // ---------------------------------------------------------------

    local procedure SendRequest(Setup: Record "MPESA Setup"; Method: Text; Path: Text; Body: SecretText; var ResponseJson: JsonObject)
    var
        Client: HttpClient;
        Request: HttpRequestMessage;
        Response: HttpResponseMessage;
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        ResponseText: Text;
        ErrorText: Text;
    begin
        Content.WriteFrom(Body);
        Content.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        Request.Method(Method);
        Request.SetRequestUri(Setup.GetBaseUrl() + Path);
        Request.Content := Content;
        Request.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', SecretStrSubstNo('Bearer %1', GetAccessToken(Setup)));

        Client.Timeout := 30000;
        Client.Send(Request, Response);
        Response.Content.ReadAs(ResponseText);

        if not ResponseJson.ReadFrom(ResponseText) then
            Error(DarajaErr, Response.HttpStatusCode(), ResponseText);

        if not Response.IsSuccessStatusCode() then begin
            ErrorText := GetJsonText(ResponseJson, 'errorMessage');
            if ErrorText = '' then
                ErrorText := ResponseText;
            if Response.HttpStatusCode() = 401 then
                ClearTokenCache();
            Error(DarajaErr, Response.HttpStatusCode(), ErrorText);
        end;
    end;

    procedure NormalizePhoneNo(PhoneNo: Text) Result: Text
    var
        Digits: Text;
    begin
        Digits := DelChr(PhoneNo, '=', DelChr(PhoneNo, '=', '0123456789'));

        case true of
            (StrLen(Digits) = 12) and (CopyStr(Digits, 1, 3) = '254'):
                Result := Digits;
            (StrLen(Digits) = 10) and (CopyStr(Digits, 1, 1) = '0'):
                Result := '254' + CopyStr(Digits, 2);
            StrLen(Digits) = 9:
                Result := '254' + Digits;
            else
                Error(InvalidPhoneErr, PhoneNo);
        end;

        if not (CopyStr(Result, 4, 1) in ['1', '7']) then
            Error(InvalidPhoneErr, PhoneNo);
    end;

    procedure GetTimestamp(): Text
    var
        EastAfricaTime: DateTime;
    begin
        // Daraja expects yyyyMMddHHmmss in East Africa Time (UTC+3).
        // Format 9 renders UTC, so shifting by three hours first gives EAT.
        EastAfricaTime := CurrentDateTime() + (3 * 60 * 60 * 1000);
        exit(DelChr(CopyStr(Format(EastAfricaTime, 0, 9), 1, 19), '=', '-T:'));
    end;

    procedure ParseDarajaDateTime(Value: Text): DateTime
    var
        Year, Month, Day, Hour, Minute, Second : Integer;
    begin
        // Daraja sends e.g. 20261023104512 (EAT).
        if StrLen(Value) <> 14 then
            exit(CurrentDateTime());
        if not (Evaluate(Year, CopyStr(Value, 1, 4)) and Evaluate(Month, CopyStr(Value, 5, 2)) and
                Evaluate(Day, CopyStr(Value, 7, 2)) and Evaluate(Hour, CopyStr(Value, 9, 2)) and
                Evaluate(Minute, CopyStr(Value, 11, 2)) and Evaluate(Second, CopyStr(Value, 13, 2)))
        then
            exit(CurrentDateTime());
        exit(CreateDateTime(DMY2Date(Day, Month, Year), 000000T + ((Hour * 3600) + (Minute * 60) + Second) * 1000));
    end;

    local procedure BuildPassword(ShortCode: Code[20]; Passkey: SecretText; Timestamp: Text): SecretText
    begin
        exit(Base64Convert.ToBase64(SecretStrSubstNo('%1%2%3', ShortCode, Passkey, Timestamp)));
    end;

    local procedure GetJsonText(Json: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Json.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    // ---------------------------------------------------------------
    // Integration events for partners and other extensions
    // ---------------------------------------------------------------

    [IntegrationEvent(false, false)]
    local procedure OnAfterStkPushInitiated(var MpesaTransaction: Record "MPESA Transaction")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStkPushCompleted(var MpesaTransaction: Record "MPESA Transaction")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterC2BRegistered(var MpesaTransaction: Record "MPESA Transaction")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeResolveAccountReference(var MpesaTransaction: Record "MPESA Transaction"; var IsHandled: Boolean)
    begin
    end;
}
