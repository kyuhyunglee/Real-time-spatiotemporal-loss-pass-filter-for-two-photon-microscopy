%% Local TIFF preprocessing test
% 이 스크립트는 Prairie View에서 저장된 TIFF를
% 30 fps 입력처럼 순서대로 읽어 처리한다.

clear;
clc;
close all;

%% 1. 프로젝트 경로 설정

projectRoot = fileparts(mfilename("fullpath"));

if strlength(projectRoot) == 0
    % 스크립트가 아직 저장되지 않았을 때의 fallback
    projectRoot = pwd;
end

srcPath = fullfile(projectRoot, "src");
dataPath = fullfile(projectRoot, "data");
outputPath = fullfile(projectRoot, "output");

addpath(srcPath);

if ~isfolder(outputPath)
    mkdir(outputPath);
end

%% 2. TIFF 파일 선택

[fileName, folderName] = uigetfile( ...
    { ...
        "*.tif;*.tiff", "TIFF files (*.tif, *.tiff)"; ...
        "*.*", "All files" ...
    }, ...
    "처리할 TIFF 파일을 선택하세요", ...
    dataPath);

if isequal(fileName, 0)
    error("파일 선택이 취소되었습니다.");
end

tiffPath = fullfile(folderName, fileName);

fprintf("\nSelected TIFF:\n%s\n\n", tiffPath);

%% 3. 처리 파라미터

config = struct();

% 최종 영상 크기
config.targetSize = [256 256];

% Prairie View의 유효 frame rate
config.frameRate = 30;

% Temporal EMA time constant
% 처음에는 0.1초로 시작
config.temporalTau = 0.1;

% Downsampled 영상 기준 Gaussian sigma
config.spatialSigma = 0.8;

config.enableTemporalDenoising = true;
config.enableSpatialDenoising = true;

% 실제 30 fps처럼 기다리면서 실행할지 여부
simulateRealtime = true;

% MATLAB 화면을 몇 프레임마다 갱신할지
displayEveryNFrames = 10;

%% 4. 입력 source와 processor 생성

source = TiffFrameSource( ...
    tiffPath, config.frameRate);

processor = ImageProcessor(config);

numFrames = source.getFrameCount();

%% 5. 출력 배열 미리 할당

outputHeight = config.targetSize(1);
outputWidth = config.targetSize(2);

processedFrames = zeros( ...
    outputHeight, ...
    outputWidth, ...
    numFrames, ...
    "single");

processingTimesMs = zeros(numFrames, 1);
sourceTimestamps = zeros(numFrames, 1);

%% 6. 결과 표시 창 만들기

figureHandle = figure( ...
    "Name", "Local Prairie Preprocessing Test", ...
    "NumberTitle", "off");

tiledlayout(1, 2);

rawAxes = nexttile;
rawImageHandle = imagesc(rawAxes, zeros(512, 512));
axis(rawAxes, "image");
axis(rawAxes, "off");
colormap(rawAxes, gray);
title(rawAxes, "Raw frame");

processedAxes = nexttile;
processedImageHandle = imagesc( ...
    processedAxes, ...
    zeros(outputHeight, outputWidth));
axis(processedAxes, "image");
axis(processedAxes, "off");
colormap(processedAxes, gray);
title(processedAxes, "Processed frame");

%% 7. 프레임 처리 루프

fprintf("\nProcessing started...\n");

framePeriod = 1 / config.frameRate;
overallTimer = tic;

frameIndex = 0;

while source.hasNextFrame()
    frameLoopTimer = tic;

    % 입력 소스에서 다음 프레임 받기
    [rawFrame, metadata] = source.nextFrame();

    % 공통 영상 처리
    [processedFrame, metrics] = ...
        processor.process(rawFrame);

    frameIndex = frameIndex + 1;

    processedFrames(:, :, frameIndex) = ...
        processedFrame;

    processingTimesMs(frameIndex) = ...
        metrics.totalMs;

    sourceTimestamps(frameIndex) = ...
        metadata.timestampSeconds;

    % GUI는 매 프레임 갱신하지 않음
    if mod(frameIndex, displayEveryNFrames) == 0 || ...
            frameIndex == 1 || ...
            frameIndex == numFrames

        set(rawImageHandle, ...
            "CData", rawFrame);

        set(processedImageHandle, ...
            "CData", processedFrame);

        title(rawAxes, ...
            sprintf("Raw frame %d / %d", ...
            frameIndex, numFrames));

        title(processedAxes, ...
            sprintf("Processed, %.2f ms", ...
            metrics.totalMs));

        drawnow limitrate;
    end

    % 30 fps 입력처럼 재생
    if simulateRealtime
        elapsedThisLoop = toc(frameLoopTimer);
        remainingTime = framePeriod - elapsedThisLoop;

        if remainingTime > 0
            pause(remainingTime);
        end
    end
end

totalElapsedSeconds = toc(overallTimer);

fprintf("Processing finished.\n\n");

%% 8. 성능 통계

meanMs = mean(processingTimesMs);
medianMs = median(processingTimesMs);
p95Ms = prctile(processingTimesMs, 95);
p99Ms = prctile(processingTimesMs, 99);
maxMs = max(processingTimesMs);

frameBudgetMs = 1000 / config.frameRate;
overBudgetCount = sum( ...
    processingTimesMs > frameBudgetMs);

fprintf("Processed frames: %d\n", frameIndex);
fprintf("Target frame budget: %.3f ms\n", frameBudgetMs);
fprintf("Mean processing time: %.3f ms\n", meanMs);
fprintf("Median processing time: %.3f ms\n", medianMs);
fprintf("95th percentile: %.3f ms\n", p95Ms);
fprintf("99th percentile: %.3f ms\n", p99Ms);
fprintf("Maximum processing time: %.3f ms\n", maxMs);
fprintf("Frames over budget: %d / %d\n", ...
    overBudgetCount, frameIndex);
fprintf("Total wall time: %.3f s\n", ...
    totalElapsedSeconds);

%% 9. 결과 MAT 파일 저장

[~, baseName, ~] = fileparts(fileName);

timestampText = string( ...
    datetime("now", "Format", "yyyyMMdd_HHmmss"));

matOutputPath = fullfile( ...
    outputPath, ...
    baseName + "_processed_" + ...
    timestampText + ".mat");

processingMetadata = struct();
processingMetadata.sourcePath = tiffPath;
processingMetadata.sourceFrameRate = config.frameRate;
processingMetadata.sourceFrameCount = numFrames;
processingMetadata.targetSize = config.targetSize;
processingMetadata.temporalTau = ...
    config.temporalTau;
processingMetadata.spatialSigma = ...
    config.spatialSigma;
processingMetadata.frameBudgetMs = ...
    frameBudgetMs;
processingMetadata.meanProcessingMs = ...
    meanMs;
processingMetadata.p99ProcessingMs = ...
    p99Ms;
processingMetadata.maxProcessingMs = ...
    maxMs;
processingMetadata.framesOverBudget = ...
    overBudgetCount;

save( ...
    matOutputPath, ...
    "processedFrames", ...
    "processingTimesMs", ...
    "sourceTimestamps", ...
    "processingMetadata", ...
    "-v7.3");

fprintf("\nMAT result saved:\n%s\n", ...
    matOutputPath);

%% 10. 처리 결과를 multipage TIFF로 저장

tiffOutputPath = fullfile( ...
    outputPath, ...
    baseName + "_processed_" + ...
    timestampText + ".tif");

% 표시 및 TIFF 저장을 위해 각 영상의 값을 uint16 범위로 변환
allMin = min(processedFrames, [], "all");
allMax = max(processedFrames, [], "all");

if allMax > allMin
    normalizedFrames = ...
        (processedFrames - allMin) ./ ...
        (allMax - allMin);
else
    normalizedFrames = ...
        zeros(size(processedFrames), "single");
end

for k = 1:numFrames
    frameForTiff = uint16( ...
        normalizedFrames(:, :, k) * 65535);

    if k == 1
        imwrite( ...
            frameForTiff, ...
            tiffOutputPath, ...
            "tif", ...
            "Compression", "none");
    else
        imwrite( ...
            frameForTiff, ...
            tiffOutputPath, ...
            "tif", ...
            "WriteMode", "append", ...
            "Compression", "none");
    end
end

fprintf("Processed TIFF saved:\n%s\n", ...
    tiffOutputPath);