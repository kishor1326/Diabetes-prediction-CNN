
%% DIABETES REPORT OCR + ML SCREENING DEMO
% Save as: diabetesReportDemo.m
% Existing model: diabetesModel.mat
% Existing files are not overwritten.
% Educational prototype only - not a medical diagnosis.

clear;
clc;

%% 1. Load existing model
projectDir = 'C:\Diabetes Prediction';
modelFile = fullfile(projectDir, 'diabetesModel.mat');

if ~isfile(modelFile)
    error('Model not found: %s. Run trainDiabetesModel.m first.', ...
        modelFile);
end

S = load(modelFile);

if ~isfield(S,'model') || ~isfield(S,'medians')
    error('Model file must contain model and medians.');
end

model = S.model;
medians = S.medians;

featureNames = {
    'Pregnancies'
    'Glucose'
    'BloodPressure'
    'SkinThickness'
    'Insulin'
    'BMI'
    'DiabetesPedigreeFunction'
    'Age'
};

%% 2. Upload report image
[filename, folder] = uigetfile( ...
    {'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
    'Blood report images (*.png, *.jpg, *.tif, *.bmp)'}, ...
    'Select a blood report image');

reportText = '';
glucoseOCR = '';
hba1cOCR = '';

if ~isequal(filename,0)

    imagePath = fullfile(folder,filename);
    reportImage = imread(imagePath);

    figure('Name','Uploaded Blood Report', ...
        'NumberTitle','off');

    imshow(reportImage);
    title('Uploaded report - verify all extracted values');

    %% 3. OCR extraction
    try
        ocrResult = ocr(reportImage);
        reportText = ocrResult.Text;

        % Prefer fasting glucose labels.
        glucoseOCR = extractLabValue(reportText, {
            'fasting blood glucose'
            'fasting plasma glucose'
            'fasting glucose'
            'blood glucose'
            'glucose'
            'fbs'
            'fpg'
        });

        hba1cOCR = extractLabValue(reportText, {
            'hba1c'
            'hb a1c'
            'glycated hemoglobin'
            'glycosylated hemoglobin'
            'a1c'
        });

        fprintf('\n===== OCR TEXT =====\n%s\n',reportText);
        fprintf('Glucose candidate: %s\n',glucoseOCR);
        fprintf('HbA1c candidate: %s\n',hba1cOCR);

    catch ME
        warning('OCR failed. Manual entry is available.');
        fprintf('OCR error: %s\n',ME.message);
    end

else
    disp('No image selected. Continue with manual entry.');
end

%% 4. Editable input form
prompts = {
    'Pregnancies (count):'
    'Glucose (mg/dL):'
    'Blood pressure (mmHg):'
    'Skin thickness (mm):'
    'Insulin (uIU/mL):'
    'BMI (kg/m^2):'
    'Diabetes pedigree function:'
    'Age (years):'
    'HbA1c (%) - optional, display only:'
};

% Only glucose and HbA1c may come from the report.
% Other inputs must be supplied by the user.
defaults = {
    ''
    glucoseOCR
    ''
    ''
    ''
    ''
    ''
    ''
    hba1cOCR
};

answers = inputdlg(prompts, ...
    'Review and confirm report values',[1 58],defaults);

if isempty(answers)
    disp('Cancelled. No prediction was made.');
    return;
end

values = nan(1,9);

for k = 1:9
    txt = strtrim(answers{k});

    if ~isempty(txt)
        values(k) = str2double(txt);
    end
end

%% 5. Validate inputs
x = values(1:8);

if any(~isfinite(x))
    errordlg(['Enter valid numeric values for all eight model ' ...
        'inputs. HbA1c may be left blank.'], ...
        'Missing or invalid input');
    return;
end

if x(1) < 0 || x(1) ~= floor(x(1)) || ...
        x(2) <= 0 || x(3) < 0 || ...
        x(4) < 0 || x(5) < 0 || ...
        x(6) < 0 || x(7) < 0 || x(8) < 1

    errordlg('Check all entered values and units.', ...
        'Invalid input');
    return;
end

if ~isnan(values(9)) && ...
        (~isfinite(values(9)) || ...
        values(9) <= 0 || values(9) > 30)

    errordlg('Enter a valid HbA1c percentage or leave it blank.', ...
        'Invalid HbA1c');
    return;
end

%% 6. Match training preprocessing
% The training script treated zero values in these features
% as missing and used training medians.
zeroAsMissing = [3 4 5 6];

for j = zeroAsMissing
    if x(j) == 0
        x(j) = medians(j);
    end
end

%% 7. Confirm glucose test type
% The threshold interpretation depends on whether glucose
% was measured fasting. Do not assume every glucose result is fasting.

[glucoseTypeIndex, glucoseTypeOK] = listdlg( ...
    'PromptString','Select the glucose test type:', ...
    'SelectionMode','single', ...
    'ListString',{'Fasting glucose','Random glucose', ...
                  'Post-meal glucose','Unknown'}, ...
    'InitialValue',4, ...
    'Name','Glucose test type');

if ~glucoseTypeOK
    disp('Cancelled by user.');
    return;
end

glucoseTypes = {'Fasting','Random','Post-meal','Unknown'};
glucoseType = glucoseTypes{glucoseTypeIndex};

%% 8. Final confirmation
summaryText = sprintf([ ...
    'Please verify the values.\n\n' ...
    'Glucose: %.2f mg/dL (%s)\n' ...
    'HbA1c: %s\n\n' ...
    'The ML model uses eight Pima dataset features.\n' ...
    'HbA1c is not used by this model.\n\n' ...
    'Proceed with prediction?'], ...
    x(2),glucoseType,formatOptional(values(9)));

choice = questdlg(summaryText, ...
    'Confirm inputs', ...
    'Confirm and Predict','Cancel','Cancel');

if ~strcmp(choice,'Confirm and Predict')
    disp('Prediction cancelled.');
    return;
end

%% 9. Predict using the existing model
try
    prediction = predict(model,x);
catch ME
    errordlg(sprintf('Model prediction failed:\n%s',ME.message), ...
        'Prediction error');
    rethrow(ME);
end

predLabel = string(prediction(1));

if predLabel == "1"
    resultTitle = 'ML output: Class 1';
    resultDescription = ...
        'Positive class in the original dataset.';
else
    resultTitle = 'ML output: Class 0';
    resultDescription = ...
        'Negative class in the original dataset. This does not rule out diabetes.';
end

%% 10. Separate report-based screening flags
% These are threshold flags, not a diagnosis.
% Fasting glucose threshold applies only when fasting is confirmed.
% HbA1c is displayed separately and is not fed to the ML model.

reportFlags = {};

if strcmp(glucoseType,'Fasting') && x(2) >= 126
    reportFlags{end+1} = ...
        'Fasting glucose is at or above 126 mg/dL.';
end

if ~isnan(values(9)) && values(9) >= 6.5
    reportFlags{end+1} = ...
        'HbA1c is at or above 6.5%.';
end

if isempty(reportFlags)
    screeningTitle = 'Report screening: No threshold flagged';
    screeningMessage = ...
        'This does not rule out diabetes. Interpret results with a clinician.';
else
    screeningTitle = ...
        'Report screening: Threshold flagged - follow-up needed';

    screeningMessage = strjoin(reportFlags,newline);
    screeningMessage = [screeningMessage newline ...
        'Laboratory results require appropriate clinical confirmation.'];
end

%% 11. Prepare dashboard data
displayNames = [featureNames; {'HbA1c (display only)'}];
displayValues = [x(:); values(9)];

displayTable = table(displayNames,displayValues, ...
    'VariableNames',{'Feature','ConfirmedValue'});

%% 12. Results dashboard
fig = uifigure( ...
    'Name','Diabetes Report Assessment', ...
    'Position',[100 100 780 610]);

uilabel(fig, ...
    'Text','DIABETES SCREENING DEMO', ...
    'Position',[25 560 730 32], ...
    'FontSize',20, ...
    'FontWeight','bold');

uilabel(fig, ...
    'Text',char(resultTitle), ...
    'Position',[25 520 730 28], ...
    'FontSize',16, ...
    'FontWeight','bold');

uilabel(fig, ...
    'Text',char(resultDescription), ...
    'Position',[25 485 730 30], ...
    'FontSize',11);

uilabel(fig, ...
    'Text',char(screeningTitle), ...
    'Position',[25 440 730 30], ...
    'FontSize',14, ...
    'FontWeight','bold');

uilabel(fig, ...
    'Text',char(screeningMessage), ...
    'Position',[25 390 730 45], ...
    'WordWrap','on', ...
    'FontSize',11);

uitable(fig, ...
    'Data',displayTable, ...
    'Position',[25 115 730 260], ...
    'ColumnWidth',{350,250});

uilabel(fig, ...
    'Text',['Educational prototype only. Neither the ML class nor ' ...
    'threshold flags provide a confirmed diagnosis. OCR can misread ' ...
    'values. Verify the original report and consult a healthcare professional.'], ...
    'Position',[25 20 730 80], ...
    'WordWrap','on', ...
    'FontSize',10);

%% 13. Print results
fprintf('\n===== PREDICTION COMPLETE =====\n');
disp(resultTitle);
disp(resultDescription);
disp(screeningTitle);
disp(screeningMessage);
disp(displayTable);

%% Local function: label-aware OCR extraction
function valueText = extractLabValue(textIn,labels)

    valueText = '';

    for n = 1:numel(labels)

        escapedLabel = regexptranslate('escape',labels{n});

        % Search for a number after the label.
        % The result is only a candidate and must be verified.
        pattern = ['(?i)' escapedLabel ...
            '[^\d\r\n]{0,50}(\d{1,3}(?:\.\d+)?)'];

        token = regexp(textIn,pattern,'tokens','once');

        if ~isempty(token)
            valueText = token{1};
            return;
        end
    end
end

%% Local function: optional HbA1c display
function out = formatOptional(value)

    if isnan(value)
        out = 'Not supplied';
    else
        out = sprintf('%.2f%%',value);
    end
end
