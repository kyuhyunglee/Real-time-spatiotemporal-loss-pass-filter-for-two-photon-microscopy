classdef ImageProcessor < handle
    %IMAGEPROCESSOR
    % 각 프레임에 다음 처리를 적용한다.
    %
    % 1. single precision 변환
    % 2. block-average downsampling
    % 3. temporal EMA denoising
    % 4. spatial Gaussian denoising

    properties
        TargetSize
        FrameRate
        TemporalTau
        SpatialSigma
        EnableTemporalDenoising
        EnableSpatialDenoising
    end

    properties (SetAccess = private)
        TemporalState
        Alpha
        ProcessedFrameCount
    end

    methods
        function obj = ImageProcessor(config)
            % config 예:
            % config.targetSize = [128 128];
            % config.frameRate = 30;
            % config.temporalTau = 0.1;
            % config.spatialSigma = 0.8;

            if nargin < 1
                config = struct();
            end

            obj.TargetSize = getConfigValue( ...
                config, "targetSize", [128 128]);

            obj.FrameRate = getConfigValue( ...
                config, "frameRate", 30);

            obj.TemporalTau = getConfigValue( ...
                config, "temporalTau", 0.1);

            obj.SpatialSigma = getConfigValue( ...
                config, "spatialSigma", 0.8);

            obj.EnableTemporalDenoising = getConfigValue( ...
                config, "enableTemporalDenoising", true);

            obj.EnableSpatialDenoising = getConfigValue( ...
                config, "enableSpatialDenoising", true);

            if obj.FrameRate <= 0
                error("FrameRate는 0보다 커야 합니다.");
            end

            if obj.TemporalTau <= 0
                error("TemporalTau는 0보다 커야 합니다.");
            end

            if obj.SpatialSigma < 0
                error("SpatialSigma는 음수가 될 수 없습니다.");
            end

            % EMA 계수:
            % alpha가 클수록 현재 프레임을 더 많이 반영
            obj.Alpha = single( ...
                1 - exp(-1 / ...
                (obj.FrameRate * obj.TemporalTau)));

            obj.TemporalState = [];
            obj.ProcessedFrameCount = 0;

            fprintf("Image processor initialized.\n");
            fprintf("  Target size: %d x %d\n", ...
                obj.TargetSize(1), obj.TargetSize(2));
            fprintf("  Frame rate: %.3f fps\n", obj.FrameRate);
            fprintf("  Temporal tau: %.3f s\n", obj.TemporalTau);
            fprintf("  EMA alpha: %.6f\n", obj.Alpha);
            fprintf("  Spatial sigma: %.3f pixels\n", ...
                obj.SpatialSigma);
        end

        function [output, metrics] = process(obj, rawFrame)
            %PROCESS 한 프레임을 처리한다.

            timerStart = tic;

            if isempty(rawFrame)
                error("입력 프레임이 비어 있습니다.");
            end

            if ~ismatrix(rawFrame)
                error("현재 코드는 2차원 grayscale frame만 지원합니다.");
            end

            % uint16 등의 원본 영상을 계산 가능한 single로 변환
            frame = single(rawFrame);

            % 1. Downsampling
            frame = obj.blockAverageDownsample( ...
                frame, obj.TargetSize);

            downsamplingElapsed = toc(timerStart);

            % 2. Temporal denoising
            temporalStart = tic;

            if obj.EnableTemporalDenoising
                if isempty(obj.TemporalState)
                    % 첫 프레임은 이전 상태가 없으므로 그대로 초기화
                    obj.TemporalState = frame;
                else
                    obj.TemporalState = ...
                        obj.Alpha .* frame + ...
                        (1 - obj.Alpha) .* obj.TemporalState;
                end

                temporalOutput = obj.TemporalState;
            else
                temporalOutput = frame;
            end

            temporalElapsed = toc(temporalStart);

            % 3. Spatial denoising
            spatialStart = tic;

            if obj.EnableSpatialDenoising && ...
                    obj.SpatialSigma > 0

                output = imgaussfilt( ...
                    temporalOutput, ...
                    obj.SpatialSigma, ...
                    "Padding", "replicate");
            else
                output = temporalOutput;
            end

            spatialElapsed = toc(spatialStart);

            obj.ProcessedFrameCount = ...
                obj.ProcessedFrameCount + 1;

            metrics = struct();
            metrics.frameIndex = obj.ProcessedFrameCount;
            metrics.downsamplingMs = ...
                downsamplingElapsed * 1000;
            metrics.temporalMs = ...
                temporalElapsed * 1000;
            metrics.spatialMs = ...
                spatialElapsed * 1000;
            metrics.totalMs = ...
                toc(timerStart) * 1000;
        end

        function reset(obj)
            % 새 acquisition을 시작할 때 temporal state 초기화
            obj.TemporalState = [];
            obj.ProcessedFrameCount = 0;
        end
    end

    methods (Access = private)
        function output = blockAverageDownsample( ...
                obj, frame, targetSize)
            %BLOCKAVERAGEDOWNSAMPLE
            % 정수 배율로 나누어지는 경우 block averaging을 수행한다.
            %
            % 예:
            % 512x512 → 128x128
            % 각 4x4 픽셀의 평균을 출력 픽셀 하나로 사용한다.

            inputHeight = size(frame, 1);
            inputWidth = size(frame, 2);

            targetHeight = targetSize(1);
            targetWidth = targetSize(2);

            heightFactor = inputHeight / targetHeight;
            widthFactor = inputWidth / targetWidth;

            canUseBlockAverage = ...
                mod(inputHeight, targetHeight) == 0 && ...
                mod(inputWidth, targetWidth) == 0;

            if canUseBlockAverage
                heightFactor = round(heightFactor);
                widthFactor = round(widthFactor);

                % reshape 순서를 명확히 하기 위해 먼저
                % [targetHeight, blockHeight,
                %  targetWidth, blockWidth] 형태로 만든다.
                reshaped = reshape( ...
                    frame, ...
                    heightFactor, ...
                    targetHeight, ...
                    widthFactor, ...
                    targetWidth);

                % 각 block 내부의 평균
                output = squeeze(mean( ...
                    mean(reshaped, 1), 3));

                % reshape 결과 축 순서 보정
                output = output';
            else
                % 해상도가 정확한 정수 배율이 아닐 경우 fallback
                output = imresize( ...
                    frame, ...
                    targetSize, ...
                    "bicubic", ...
                    "Antialiasing", true);
            end
        end
    end
end


function value = getConfigValue(config, fieldName, defaultValue)
%GETCONFIGVALUE config에 값이 있으면 사용하고 없으면 기본값 사용

    if isfield(config, fieldName)
        value = config.(fieldName);
    else
        value = defaultValue;
    end
end