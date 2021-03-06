{******************************************************************************}
{                       CnPack For Delphi/C++Builder                           }
{                     中国人自己的开放源码第三方开发包                         }
{                   (C)Copyright 2001-2014 CnPack 开发组                       }
{                   ------------------------------------                       }
{                                                                              }
{            本开发包是开源的自由软件，您可以遵照 CnPack 的发布协议来修        }
{        改和重新发布这一程序。                                                }
{                                                                              }
{            发布这一开发包的目的是希望它有用，但没有任何担保。甚至没有        }
{        适合特定目的而隐含的担保。更详细的情况请参阅 CnPack 发布协议。        }
{                                                                              }
{            您应该已经和开发包一起收到一份 CnPack 发布协议的副本。如果        }
{        还没有，可访问我们的网站：                                            }
{                                                                              }
{            网站地址：http://www.cnpack.org                                   }
{            电子邮件：master@cnpack.org                                       }
{                                                                              }
{******************************************************************************}

unit CnCppCodeParser;
{* |<PRE>
================================================================================
* 软件名称：CnPack IDE 专家包
* 单元名称：C/C++ 源代码分析器
* 单元作者：刘啸 liuxiao@cnpack.org
* 备    注：
* 开发平台：PWin2000Pro + Delphi 5.01
* 兼容测试：
* 本 地 化：该单元中的字符串均符合本地化处理方式
* 单元标识：$Id$
* 修改记录：2012.02.07
*               UTF8的位置转换去除后仍有问题，恢复之
*           2011.11.29
*               XE/XE2 的位置解析无需UTF8的位置转换
*           2011.05.29
*               修正BDS下对汉字UTF8未处理而导致解析出错的问题
*           2009.04.10
*               创建单元
================================================================================
|</PRE>}

interface

{$I CnWizards.inc}

uses
  Windows, SysUtils, Classes, Contnrs, CnPasCodeParser, 
  mwBCBTokenList, CnCommon, CnFastList;
  
type

//==============================================================================
// C/C++ 解析器封装类，目前只实现解析大括号层次与普通标识符位置的功能
//==============================================================================

{ TCnCppStructureParser }

  TCnCppToken = class(TCnPasToken)
  {* 描述一 Token 的结构高亮信息}
  private

  public
    constructor Create;
  published

  end;

  TCnCppStructureParser = class(TObject)
  {* 利用 CParser 进行语法解析得到各个 Token 和位置信息}
  private
    FBlockCloseToken: TCnCppToken;
    FBlockStartToken: TCnCppToken;
    FChildCloseToken: TCnCppToken;
    FChildStartToken: TCnCppToken;
    FCurrentChildMethod: AnsiString;
    FCurrentMethod: AnsiString;
    FList: TCnList;
    FMethodCloseToken: TCnCppToken;
    FMethodStartToken: TCnCppToken;
    FInnerBlockCloseToken: TCnCppToken;
    FInnerBlockStartToken: TCnCppToken;
    FCurrentClass: AnsiString;
    FSource: PAnsiChar;
    function GetCount: Integer;
    function GetToken(Index: Integer): TCnCppToken;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure ParseSource(ASource: PAnsiChar; Size: Integer; CurrLine: Integer = 0;
      CurCol: Integer = 0; ParseCurrent: Boolean = False);
    function IndexOfToken(Token: TCnCppToken): Integer;
    property Count: Integer read GetCount;
    property Tokens[Index: Integer]: TCnCppToken read GetToken;
    property MethodStartToken: TCnCppToken read FMethodStartToken;
    property MethodCloseToken: TCnCppToken read FMethodCloseToken;
    property ChildStartToken: TCnCppToken read FChildStartToken;
    property ChildCloseToken: TCnCppToken read FChildCloseToken;
    {* 当前层次为 2 的大括号}
    property BlockStartToken: TCnCppToken read FBlockStartToken;
    property BlockCloseToken: TCnCppToken read FBlockCloseToken;
    {* 当前层次为 1 的大括号}
    property InnerBlockStartToken: TCnCppToken read FInnerBlockStartToken;
    property InnerBlockCloseToken: TCnCppToken read FInnerBlockCloseToken;
    {* 当前最内层次的大括号}
    property CurrentMethod: AnsiString read FCurrentMethod;
    property CurrentClass: AnsiString read FCurrentClass;
    property CurrentChildMethod: AnsiString read FCurrentChildMethod;

    property Source: PAnsiChar read FSource;
  end;

function ParseCppCodePosInfo(const Source: AnsiString; CurrPos: Integer;
  FullSource: Boolean = True; IsUtf8: Boolean = False): TCodePosInfo;
{* 分析源代码中当前位置的信息}

implementation

var
  TokenPool: TCnList;

// 用池方式来管理 PasTokens 以提高性能
function CreateCppToken: TCnCppToken;
begin
  if TokenPool.Count > 0 then
  begin
    Result := TCnCppToken(TokenPool.Last);
    TokenPool.Delete(TokenPool.Count - 1);
  end
  else
    Result := TCnCppToken.Create;
end;

procedure FreeCppToken(Token: TCnCppToken);
begin
  if Token <> nil then
  begin
    Token.Clear;
    TokenPool.Add(Token);
  end;
end;

procedure ClearTokenPool;
var
  I: Integer;
begin
  for I := 0 to TokenPool.Count - 1 do
    TObject(TokenPool[I]).Free;
end;

//==============================================================================
// C/C++ 解析器封装类
//==============================================================================

{ TCnCppStructureParser }

constructor TCnCppStructureParser.Create;
begin
  inherited;
  FList := TCnList.Create;
end;

destructor TCnCppStructureParser.Destroy;
begin
  FList.Free;
  inherited;
end;

procedure TCnCppStructureParser.Clear;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    FreeCppToken(TCnCppToken(FList[I]));
  FList.Clear;
  FMethodStartToken := nil;
  FMethodCloseToken := nil;
  FChildStartToken := nil;
  FChildCloseToken := nil;
  FBlockStartToken := nil;
  FBlockCloseToken := nil;
  FCurrentMethod := '';
  FCurrentChildMethod := '';
end;

function TCnCppStructureParser.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TCnCppStructureParser.GetToken(Index: Integer): TCnCppToken;
begin
  Result := TCnCppToken(FList[Index]);
end;

procedure TCnCppStructureParser.ParseSource(ASource: PAnsiChar; Size: Integer;
  CurrLine: Integer; CurCol: Integer; ParseCurrent: Boolean);
const
  IdentToIgnore: array[0..2] of string = ('CATCH', 'CATCH_ALL', 'AND_CATCH_ALL');
var
  CParser: TBCBTokenList;
  Token: TCnCppToken;
  Layer: Integer;
  BraceStack: TStack;
  Brace1Stack: TStack;
  Brace2Stack: TStack;
  BraceStartToken: TCnCppToken;
  BeginBracePosition: Integer;
  FunctionName, OwnerClass: string;
  PrevIsOperator: Boolean;

  procedure NewToken;
  var
    Len: Integer;
  begin
    Token := CreateCppToken;
    Token.FTokenPos := CParser.RunPosition;

    Len := CParser.TokenLength;
    if Len > CN_TOKEN_MAX_SIZE then
      Len := CN_TOKEN_MAX_SIZE;
    FillChar(Token.FToken[0], SizeOf(Token.FToken), 0);
    CopyMemory(@Token.FToken[0], CParser.TokenAddr, Len);

    // Token.FToken := AnsiString(CParser.RunToken);

    Token.FLineNumber := CParser.RunLineNumber;
    Token.FCharIndex := CParser.RunColNumber;
    Token.FCppTokenKind := CParser.RunID;
    Token.FItemLayer := Layer;
    Token.FItemIndex := FList.Count;
    FList.Add(Token);
  end;

  function CompareLineCol(Line1, Line2, Col1, Col2: Integer): Integer;
  begin
    if Line1 < Line2 then
      Result := -1
    else if Line1 = Line2 then
    begin
      if Col1 < Col2 then
        Result := -1
      else if Col1 > Col2 then
        Result := 1
      else
        Result := 0;
    end
    else
      Result := 1;
  end;

  // 碰到()时往回越过
  procedure SkipProcedureParameters;
  var
    RoundCount: Integer;
  begin
    RoundCount := 0;
    repeat
      CParser.Previous;
      case CParser.RunID of
        ctkroundclose: Inc(RoundCount);
        ctkroundopen: Dec(RoundCount);
        ctknull: Exit;
      end;
    until ((RoundCount <= 0) and ((CParser.RunID = ctkroundopen) or
      (CParser.RunID = ctkroundpair)));
    CParser.PreviousNonJunk; // 往回跳过圆括号中的声明
  end;

  function IdentCanbeIgnore(const Name: string): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := Low(IdentToIgnore) to High(IdentToIgnore) do
    begin
      if Name = IdentToIgnore[I] then
      begin
        Result := True;
        Break;
      end;
    end;
  end;

  // 碰到<>时往回越过
  procedure SkipTemplateArgs;
  var
    TemplateCount: Integer;
  begin
    if CParser.RunID <> ctkGreater then Exit;
    TemplateCount := 1;
    repeat
      CParser.Previous;
      case CParser.RunID of
        ctkGreater: Inc(TemplateCount);
        ctklower: Dec(TemplateCount);
        ctknull: Exit;
      end;
    until (((TemplateCount = 0) and (CParser.RunID = ctklower)) or
      (CParser.RunIndex = 0));
    CParser.PreviousNonJunk;
  end;

begin
  Clear;
  CParser := nil;
  BraceStack := nil;
  Brace1Stack := nil;
  Brace2Stack := nil;

  FInnerBlockStartToken := nil;
  FInnerBlockCloseToken := nil;
  FBlockStartToken := nil;
  FBlockCloseToken := nil;

  FCurrentClass := '';
  FCurrentMethod := '';

  try
    BraceStack := TStack.Create;
    Brace1Stack := TStack.Create;
    Brace2Stack := TStack.Create;
    FSource := ASource;

    CParser := TBCBTokenList.Create;
    CParser.SetOrigin(ASource, Size);

    Layer := 0; // 初始层次，最外层为 0
    while CParser.RunID <> ctknull do
    begin
      case CParser.RunID of
        ctkbraceopen:
          begin
            Inc(Layer);
            NewToken;

            if CompareLineCol(CParser.RunLineNumber, CurrLine,
              CParser.RunColNumber, CurCol) <= 0 then // 在光标前
            begin
              BraceStack.Push(Token);
              if Layer = 1 then // 如果是第一层，又是 OuterBlock 的 Begin
                Brace1Stack.Push(Token)
              else if Layer = 2 then
                Brace2Stack.Push(Token);
            end
            else // 一旦在光标后了，就可以判断Start了
            begin
              if (FInnerBlockStartToken = nil) and (BraceStack.Count > 0) then
                FInnerBlockStartToken := TCnCppToken(BraceStack.Pop);
              if (FBlockStartToken = nil) and (Brace1Stack.Count > 0) then
                FBlockStartToken := TCnCppToken(Brace1Stack.Pop);
              if (FChildStartToken = nil) and (Brace2Stack.Count > 0) then
                FChildStartToken := TCnCppToken(Brace2Stack.Pop);
            end;
          end;
        ctkbraceclose:
          begin
            NewToken;
            if CompareLineCol(CParser.RunLineNumber, CurrLine,
              CParser.RunColNumber, CurCol) >= 0 then // 一旦在光标后了就可判断
            begin
              if (FInnerBlockStartToken = nil) and (BraceStack.Count > 0) then
                FInnerBlockStartToken := TCnCppToken(BraceStack.Pop);
              if (FBlockStartToken = nil) and (Brace1Stack.Count > 0) then
                FBlockStartToken := TCnCppToken(Brace1Stack.Pop);
              if (FChildStartToken = nil) and (Brace2Stack.Count > 0) then
                FChildStartToken := TCnCppToken(Brace2Stack.Pop);

              if (FInnerBlockCloseToken = nil) and (FInnerBlockStartToken <> nil) then
              begin
                if Layer = FInnerBlockStartToken.ItemLayer then
                  FInnerBlockCloseToken := Token;
              end;

              if Layer = 1  then // 第一层，为 OuterBlock 的 End
              begin
                if FBlockCloseToken = nil then
                  FBlockCloseToken := Token;
              end
              else if Layer = 2 then  // 第二层的也记着
              begin
                if FChildCloseToken = nil then
                  FChildCloseToken := Token;
              end;
            end
            else // 在光标前
            begin
              if BraceStack.Count > 0 then
                BraceStack.Pop;
              if (Layer = 1) and (Brace1Stack.Count > 0) then
                Brace1Stack.Pop;
              if (Layer = 2) and (Brace2Stack.Count > 0) then
                Brace2Stack.Pop;
            end;
            Dec(Layer);
          end;
        ctkidentifier,        // Need this 4 for flow control in source highlight
        ctkreturn, ctkgoto, ctkbreak, ctkcontinue:
          begin
            NewToken;
          end;
      end;

      CParser.NextNonJunk;
    end;

    if ParseCurrent then
    begin
      // DONE: 处理第一层或第二层（如果第一层是 namespace 的话）的内容
      if FBlockStartToken <> nil then
      begin
        BraceStartToken := FBlockStartToken;

        // 先到达最外层括号处
        if CParser.RunPosition > FBlockStartToken.TokenPos then
        begin
          while CParser.RunPosition > FBlockStartToken.TokenPos do
            CParser.PreviousNonJunk;
        end
        else if CParser.RunPosition < FBlockStartToken.TokenPos then
          while CParser.RunPosition < FBlockStartToken.TokenPos do
            CParser.NextNonJunk;

        while not (CParser.RunID in [ctkNull, ctkbraceclose])
          and (CParser.RunPosition > 0) do
        begin
          if CParser.RunID in [ctknamespace] then
          begin
            // 本层是 namespace，处理第二层去
            BraceStartToken := FChildStartToken;
            Break;
          end;
          CParser.PreviousNonJunk;
        end;

        if BraceStartToken = nil then
          Exit;

        // 回到最外层括号处
        if CParser.RunPosition > BraceStartToken.TokenPos then
        begin
          while CParser.RunPosition > BraceStartToken.TokenPos do
            CParser.PreviousNonJunk;
        end
        else if CParser.RunPosition < BraceStartToken.TokenPos then
          while CParser.RunPosition < BraceStartToken.TokenPos do
            CParser.NextNonJunk;

        // 查找这个需要的大括号之前的声明，类或函数等
        BeginBracePosition := CParser.RunPosition;
        // 记录左大括号的位置
        CParser.PreviousNonJunk;
        if CParser.RunID = ctkidentifier then // 如果左大括号前是标识符
        begin
          while not (CParser.RunID in [ctkNull, ctkbraceclose])
            and (CParser.RunPosition > 0) do
          begin
            if CParser.RunID in [ctkclass, ctkstruct] then
            begin
              // 找到个 class 或 struct，那么名称是紧靠 : 或 { 前的东西
              while not (CParser.RunID in [ctkcolon, ctkbraceopen, ctknull]) do
              begin
                FCurrentClass := AnsiString(CParser.RunToken); // 找到类名或者结构名
                CParser.NextNonJunk;
              end;
              if FCurrentClass <> '' then // 找到类名了，不会有其它名称了，退出
                Exit;
            end;
            CParser.PreviousNonJunk;
          end;
        end
        else if CParser.RunID in [ctkroundclose, ctkroundpair, ctkconst,
          ctkvolatile, ctknull] then
        begin
          // 左大括号前不是标识符而是这几个，则可能到达了一个函数体的末尾，大括号开头
          // 往回走，解出函数来
          CParser.Previous;

          // 往回找圆括号等
          while not ((CParser.RunID in [ctkSemiColon, ctkbraceclose,
            ctkbraceopen, ctkbracepair]) or (CParser.RunID in IdentDirect) or
            (CParser.RunIndex = 0)) do
          begin
            CParser.PreviousNonJunk;
            // 同时处理函数中的冒号，如 __fastcall TForm1::TForm1(TComponent* Owner) : TForm(Owner)
            if CParser.RunID = ctkcolon then
            begin
              CParser.PreviousNonJunk;
              if CParser.RunID in [ctkroundclose, ctkroundpair] then
                CParser.NextNonJunk
              else
              begin
                CParser.NextNonJunk;
                Break;
              end;
            end;
          end;

          // 这儿应该停在圆括号处
          if CParser.RunID in [ctkcolon, ctkSemiColon, ctkbraceclose,
            ctkbraceopen, ctkbracepair] then
            CParser.NextNonComment
          else if CParser.RunIndex = 0 then
          begin
            if CParser.IsJunk then
              CParser.NextNonJunk;
          end
          else // 越过编译指令
          begin
            while CParser.RunID <> ctkcrlf do
            begin
              if (CParser.RunID = ctknull) then
                Exit;
              CParser.Next;
            end;
            CParser.NextNonJunk;
          end;

          // 到达一个具体的函数开头
          while (CParser.RunPosition < BeginBracePosition) and
            (CParser.RunID <> ctkcolon) do
          begin
            if CParser.RunID = ctknull then
              Exit;
            CParser.NextNonComment;
          end;

          FunctionName := '';
          OwnerClass := '';
          SkipProcedureParameters;

          if CParser.RunID = ctknull then
            Exit
          else if CParser.RunID = ctkthrow then
            SkipProcedureParameters;

          CParser.PreviousNonJunk;
          PrevIsOperator := CParser.RunID = ctkoperator;
          CParser.NextNonJunk;

          if ((CParser.RunID = ctkidentifier) or (PrevIsOperator)) and not
            IdentCanbeIgnore(CParser.RunToken) then
          begin
            if PrevIsOperator then
              FunctionName := 'operator ';
            FunctionName := FunctionName + CParser.RunToken;
            CParser.PreviousNonJunk;

            if CParser.RunID = ctkcoloncolon then
            begin
              FCurrentClass := '';
              while CParser.RunID = ctkcoloncolon do
              begin
                CParser.PreviousNonJunk; // 类名或类名带尖括号
                if CParser.RunID = ctkGreater then
                  SkipTemplateArgs;

                OwnerClass := CParser.RunToken + OwnerClass;
                CParser.PreviousNonJunk;
                if CParser.RunID = ctkcoloncolon then
                  OwnerClass := CParser.RunToken + OwnerClass;
              end;
              FCurrentClass := AnsiString(OwnerClass);
            end;
            if OwnerClass <> '' then
              FCurrentMethod := AnsiString(OwnerClass + '::' + FunctionName)
            else
              FCurrentMethod := AnsiString(FunctionName);
          end;
        end;
      end;
    end;
  finally
    BraceStack.Free;
    Brace1Stack.Free;
    Brace2Stack.Free;
    CParser.Free;
  end;
end;

function TCnCppStructureParser.IndexOfToken(Token: TCnCppToken): Integer;
begin
  Result := FList.IndexOf(Token);
end;

{ TCnCppToken }

constructor TCnCppToken.Create;
begin
  inherited;
  FUseAsC := True;
end;

// 分析源代码中当前位置的信息
function ParseCppCodePosInfo(const Source: AnsiString; CurrPos: Integer;
  FullSource: Boolean = True; IsUtf8: Boolean = False): TCodePosInfo;
var
  CanExit: Boolean;
  CParser: TBCBTokenList;
  Text: AnsiString;

  procedure DoNext;
  var
    OldPosition: Integer;
  begin
    Result.LineNumber := CParser.RunLineNumber - 1;
    Result.LinePos := CParser.RunColNumber;
    Result.TokenPos := CParser.RunPosition;
    Result.Token := AnsiString(CParser.RunToken);
    Result.CTokenID := CParser.RunID;

    OldPosition := CParser.RunPosition;
    CParser.Next;

    CanExit := CParser.RunPosition = OldPosition;
    // 当 Next 再也前进不了的时候，就是该撤了
    // 这样做的原因是，CParser 在结尾时，有时候不会进行到ctknull，而一直打转
  end;
begin
  if CurrPos <= 0 then
    CurrPos := MaxInt;
  CParser := nil;
  Result.IsPascal := False;

  try
    CParser := TBCBTokenList.Create;
    CParser.DirectivesAsComments := False;
{$IFDEF BDS}
    if IsUtf8 then
    begin
      Text := CnUtf8ToAnsi(PAnsiChar(Source));
//{$IFNDEF BDS2009_UP}
      // XE/XE2 下的CurrPos 已经是 UTF8 的位置，无需再次转换，否则出错。2009 未知。
      CurrPos := Length(CnUtf8ToAnsi(Copy(Source, 1, CurrPos)));
      // 不转换会导致其他问题如字符串里弹出代码助手，还是得转。
//{$ENDIF}
    end
    else
      Text := Source;
{$ELSE}
    Text := Source;
{$ENDIF}
    CParser.SetOrigin(PAnsiChar(Text), Length(Text));

    if FullSource then
    begin
      Result.AreaKind := akHead; // 未使用
      Result.PosKind := pkField; // 常规空白区，以pkField
    end
    else
    begin

    end;

    while (CParser.RunPosition < CurrPos) and (CParser.RunID <> ctknull) do
    begin
      // 至少要区分出字符（串）、注释、->或.后、标识符、编译指令等
      case CParser.RunID of
        ctkansicomment, ctkslashescomment:
          begin
            Result.PosKind := pkComment;
          end;
        ctkstring:
          begin
            Result.PosKind := pkString;
          end;
        ctkcrlf:
          begin
            // 行注释与#编译指令，以回车结尾
            if (Result.PosKind = pkCompDirect) or (Result.CTokenID = ctkslashescomment) then
              Result.PosKind := pkField;
          end;
//        ctksemicolon, ctkbraceopen, ctkbraceclose, ctkbracepair,
//        ctkint, ctkfloat, ctkdouble, ctkchar,
//        ctkidentifier, ctkcoloncolon,
//        ctkroundopen, ctkroundpair, ctksquareopen, ctksquarepair,
//        ctkcomma, ctkequal, ctknumber:
//          begin
//            Result.PosKind := pkField;
//          end;
        ctkselectelement:
          begin
            Result.PosKind := pkFieldDot; // -> 视作 . 处理
          end;
        ctkpoint:
          begin
            if Result.CTokenID = ctkidentifier then
              Result.PosKind := pkFieldDot; // 上一个标识符后的点才算
          end;
        ctkdirdefine, ctkdirelif, ctkdirelse, ctkdirendif, ctkdirerror, ctkdirif,
        ctkdirifdef, ctkdirifndef, ctkdirinclude, ctkdirline, ctkdirnull,
        ctkdirpragma, ctkdirundef:
          begin
            Result.PosKind := pkCompDirect;
          end;
        ctkUnknown:
          begin
            // #后的编译指令未完成时
            if (Length(CParser.RunToken) >= 1 ) and (CParser.RunToken[1] = '#') then
            begin
              Result.PosKind := pkCompDirect;
            end
            else
              Result.PosKind := pkField;
          end;
      else
        Result.PosKind := pkField;
      end;

      DoNext;
      if CanExit then
        Break;
    end;
  finally
    CParser.Free;
  end;
end;

initialization
  TokenPool := TCnList.Create;

finalization
  ClearTokenPool;
  FreeAndNil(TokenPool);

end.
