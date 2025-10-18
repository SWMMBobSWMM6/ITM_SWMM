unit Dabout;

{-------------------------------------------------------------------}
{                    Unit:    Dabout.pas                            }
{                    Project: ITM SWMM                              }
{                    Version: 1.0                                   }
{                    Date:    09/01/24                              }
{                    Author:  L. Rossman                            }
{                                                                   }
{   Form unit containing the "About" dialog box for ITM SWMM.       }
{-------------------------------------------------------------------}

interface

uses Windows, Types, Classes, Graphics, Forms, Controls, StdCtrls,
  Buttons, ExtCtrls, ComCtrls, Vcl.Imaging.GIFImg, ShellAPI,
  Vcl.Imaging.pngimage;

type
  TAboutBoxForm = class(TForm)
    Button1: TButton;
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    Memo1: TMemo;
    Memo2: TMemo;
    Label3: TLabel;
    Label6: TLabel;
    Image3: TImage;
    Panel2: TPanel;
    Image2: TImage;
    Label4: TLabel;
    procedure FormKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

//var
//  AboutBoxForm: TAboutBoxForm;

implementation

{$R *.DFM}

const

Description1 =
'ITM SWMM is a fork of the public domain U.S. EPA Storm Water '+
'Management Model that includes the Illinois Transient Model (ITM) '+
'as an optional flow routing method. '#13#10#13#10+
'SWMM is a distrbuted rainfall-runoff-routing simulation model used '+
'for single event or long-term (continuous) simulation of runoff quantity '+
'and quality from primarily urban areas.'#13#10#13#10+
'ITM is a finite-volume shock-capturing model for simulating the dynamics '+
'of rapidly filling and draining sewer systems.';

Description2 =
'ITM SWMM is open source software that may be freely copied and distributed.';

Disclaimer =
'This software is provided on an "as-is" basis. The authors and '+
'Florida International University (FIU) make no '+
'representations or warranties of any kind and expressly disclaim '+
'all other warranties express or implied, including, without '+
'limitation, warranties of merchantability or fitness for a particular '+
'purpose. Although care has been used in preparing the software product, '+
'the authors and FIU disclaim all liability '+
'for its accuracy or completeness, and the user shall be solely responsible '+
'for the selection, use, efficiency and suitability of the software product. '+
'Any person who uses this product does so at their sole risk and without '+
'liability to the authors or FIU. The authors and FIU shall have no liability '+
'to users for the infringement of proprietary rights by the software product '+
'or any portion thereof.';

procedure TAboutBoxForm.FormCreate(Sender: TObject);
begin
  Label4.Caption := 'Storm Water Management Model - ITM Edition';
  Label4.StyleElements := Label4.StyleElements - [seFont];
  Label4.Font.Color := clBlue;

{$IFDEF WIN64}
  Label6.Caption := '64-bit Edition';
{$ENDIF}

  Memo1.Lines.Add(Disclaimer);
  Memo2.Lines.Add(Description1);
  Memo2.Lines.Add('');
  Memo2.Lines.Add(Description2);
  ActiveControl := Button1;
end;

procedure TAboutBoxForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then Close;
end;

end.
