
clear; clc; close all;
rng(42);

%% 1. Load dataset
T = readtable('diabetes.csv');

% Verify dataset
disp("Dataset size:");
disp(size(T));

%% 2. Prepare features and target
X = T{:, 1:8};
Y = categorical(T.Outcome);

% Check for missing or invalid values
disp("Missing values in each feature:");
disp(sum(ismissing(T(:,1:8))));

% Replace impossible zero measurements with NaN
% for the affected physiological features
zeroCols = {'Glucose','BloodPressure', ...
    'SkinThickness','Insulin','BMI'};

for i = 1:numel(zeroCols)
    col = zeroCols{i};
    T.(col)(T.(col) == 0) = NaN;
end

% Median imputation, fitted using training data only
X = T{:,1:8};

%% 3. Stratified train/test split
cv = cvpartition(Y, 'HoldOut', 0.20);

XTrain = X(training(cv), :);
YTrain = Y(training(cv));

XTest = X(test(cv), :);
YTest = Y(test(cv));

% Impute missing values using training-set medians
medians = median(XTrain, 1, 'omitnan');
medians(isnan(medians)) = 0;

for j = 1:size(XTrain,2)
    XTrain(isnan(XTrain(:,j)),j) = medians(j);
    XTest(isnan(XTest(:,j)),j) = medians(j);
end

%% 4. Train Decision Tree
model = fitctree(XTrain, YTrain, ...
    'PredictorNames', T.Properties.VariableNames(1:8));

%% 5. Predict test data
YPred = predict(model, XTest);

%% 6. Evaluate model
figure('Name','Diabetes Model Evaluation');

confusionchart(YTest, YPred);
title('Diabetes Prediction - Test Set');

accuracy = mean(YPred == YTest) * 100;

disp("Test Accuracy (%):");
disp(accuracy);

disp("Confusion Matrix:");
disp(confusionmat(YTest, YPred));

%% 7. Save trained model and preprocessing values
save('diabetesModel.mat', 'model', 'medians');

fprintf('\nModel saved as diabetesModel.mat\n');
fprintf('Baseline training complete.\n');
