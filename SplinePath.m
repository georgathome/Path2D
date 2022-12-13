classdef (InferiorClasses = {?matlab.graphics.axis.Axes}) SplinePath < Path2D
%SPLINEPATH     Spline path.
%   Path representation using splines.
% 
%   SPLINEPATH properties:
%   Breaks - Break points.
%   Coefs - Polynomial coefficients.
% 
%   SPLINEPATH methods:
%   SplinePath - Constructor.
%   mkpp - Create piecewise polynomial structure.
%   See superclasses.
% 
%   SPLINEPATH static methods:
%   See superclasses.
% 
%   See also PATH2D, MKPP.

    properties (SetAccess = private)
        % Breaks - Break points
        %   Specified as a vector of length N+1.
        Breaks = 0
        
        % Coefs - Polynomial coefficients
        %   Specified as an array of size 2-by-N-by-Np, i.e. x/y-by-number
        %   of pieces-by-polynomial coefficients in descending order. E.g.
        %   coefs(1,i,:) contains the local x-coefficients for the interval
        %   [breaks(i) breaks(i+1)].
        Coefs = zeros(2,0,4)
    end
    
    properties (Access = private)
        % ArcLengths - Cumulative length of spline segments
        ArcLengths = 0;
    end
    
    
    methods
        
        function obj = SplinePath(breaks, coefs, s, isCircuit)
        %SPLINEPATH     Create spline path object.
        %   OBJ = SPLINEPATH(BREAKS,COEFS) creates a spline path OBJ with
        %   breaks BREAKS of size 1-by-(N+1) and coefficients COEFS of size
        %   2-by-N-by-K, where N is the number of spline segments and K-1
        %   the polynomial degree.
        %
        %   OBJ = SPLINEPATH(___,ISCIRCUIT) set to true if the path is a
        %   circuit.
        %
        
            if nargin < 1
                % Return with default values
                return
            end
            
            assert(size(coefs,1) == 2, 'Spline must be 2D valued!');
            assert(isequal(numel(breaks)-1, size(coefs,2)), ...
                'Number of breaks and spline segments does not match!');
            obj.Breaks = breaks;
            obj.Coefs = coefs;
            
            if (nargin < 3) || isempty(s)
                pp = mkpp(breaks, coefs, 2);
                N = obj.numel();
                s = coder.nullcopy(zeros(N+1,1));
                s(1) = 0;
                for i = 1:N
                    tau = linspace(breaks(i), breaks(i+1), 1000);
                    dxy = diff(ppval(pp, tau), 1, 2);
                    s(i+1) = s(i) + sum(hypot(dxy(1,:), dxy(2,:)));
                end
            end
            assert(numel(s) == numel(breaks));
            obj.ArcLengths = s - s(1); % Make sure first element is zero!
            
            
            if nargin < 4
                obj = obj.setIsCircuit(1e-5);
            else
                obj.IsCircuit = isCircuit;
            end%if
            
        end%Constructor
        
        function obj = append(obj, obj2)
            
            breaks = obj.Breaks;
            coefs = obj.Coefs;
            arcLen = obj.ArcLengths;
            
            obj.Breaks = [breaks, breaks(end) + obj2.Breaks(2:end)];
            
            [~,~,k] = size(coefs);
            [~,n2,k2] = size(obj2.Coefs);
            assert(k2 <= k, 'Degree of path to append must not exceed degree of initial path!')
            obj.Coefs = cat(2, coefs, cat(3, zeros(2,n2,k-k2), obj2.Coefs));
            
            [~,P1] = obj.termPoints();
            P0 = obj2.termPoints();
            ds = sqrt( sum((P0 - P1).^2) );
            obj.ArcLengths = [arcLen; obj2.ArcLengths(2:end) + arcLen(end) + ds];
            
        end%fcn
        
        function [sd,Q,idx,tau,dphi] = cart2frenet(obj, xy, phiMax, doPlot)
            
            if nargin < 4
                doPlot = false;
                if nargin < 3
                    phiMax = [];
                end
            end
            
            [Q,idx,tau,dphi] = obj.pointProjection(xy, phiMax, doPlot);
            if isempty(Q)
                % Find the waypoint closest to point of interest
                error('Not implemented!')
            end%if
            
            % Get the orientation vector related with Q to calculate the
            % sign of distance from point of interest to path
            ppd = ppdiff(obj.mkpp());
            u = ppval(ppd, tau)' - Q;
            
            % Get sign via z-component of cross product U x (Q-XY)
            qp = bsxfun(@minus, Q, xy(:)');
            signD = sign(u(:,1).*qp(:,2) - u(:,2).*qp(:,1));
            
            sd = [obj.lengthIdxTau(idx, tau), ...
                signD.*hypot(qp(:,1), qp(:,2))];
            
        end%fcn
        
        function [tauL,tauU] = domain(obj)
            if obj.isempty()
                tauL = NaN;
                tauU = NaN;
            else
                tauL = obj.Breaks(1);
                tauU = obj.Breaks(end);
            end
        end%fcn
        
        function [x,y,tau,head,curv] = eval(obj, tau)
            
            if nargin < 2
                breaks = obj.Breaks;
                
                % M samples per spline segment + 1 sample for end point
                M = 100;
                N = obj.numel();
                tau = coder.nullcopy(zeros(N*M + 1, 1));
                for i = 1:N
                    % To avoid repeated break entries, overwrite end break
                    % of preceeding segment with initial (and equal) break
                    % of current segment
                    ii = (i-1)*M + 1;
                    jj = ii + M;
                    tau(ii:jj) = linspace(breaks(i), breaks(i+1), M+1);
                end
                tau(end) = breaks(end);
            else
                % Avoid PPVAL returning 3D arrays for empty evaluation
                % sites by applying (:)
                tau = tau(:);
            end%if
            
            if obj.isempty()
                N = numel(tau);
                tau(:) = NaN;
                x = NaN(N, 1);
                y = NaN(N, 1);
                head = NaN(N, 1);
                curv = NaN(N, 1);
                return
            end
            
            % Set tau to NaN outside spline domain so that corresponding
            % return values are NaN too.
            tau((tau < obj.Breaks(1)) | (tau > obj.Breaks(end))) = NaN;
            
            % Make use of PPVAL for spline evaluation
            pp = obj.mkpp();
            xy = ppval(pp, tau)';
            x = xy(:,1);
            y = xy(:,2);
            
            if nargout > 3
                ppD1 = ppdiff(pp);
                xyD1 = ppval(ppD1, tau);
                head = cx2Heading(xyD1(1,:), xyD1(2,:))';
                
                if nargout > 4
                    ppD2 = ppdiff(ppD1);
                    xyD2 = ppval(ppD2, tau);
                    curv = cx2Curvature(xyD1(1,:), xyD1(2,:), xyD2(1,:), xyD2(2,:))';
                end
            end%if
            
        end%fcn
        
        function [xy,Q,idx,tau] = frenet2cart(obj, sd, doPlot)
            
            % Get the indexes referring to the path segments according to
            % the frenet coordinates s-values
            sEval = sd(:,1);
            if obj.IsCircuit
                sEval = mod(sEval, obj.length());
            end
            S = obj.ArcLengths;
            idx = coder.nullcopy(zeros(size(sEval), 'uint32'));
            for i = 1:numel(sEval)
                idxs = find(sEval(i) < S, 1, 'first');
                if isempty(idxs)
                    idx(i) = numel(S);
                else
                    idx(i) = idxs(1) - 1;
                end
            end%for
            
            % The points on the path (i.e. d=0) are given by the segment's
            % initial point plus the remaining length along the current
            % segment
            ds = sEval - S(idx);
            breaks = obj.Breaks';
            tau = breaks(idx);
            tau = tau + ds./(S(idx+1) - S(idx)).*(breaks(idx+1) - tau);
            
            [x,y] = obj.eval(tau);
            n = ppval(ppdiff(obj.mkpp()), tau)';
            Q = [x,y];
            xy = Q + bsxfun(@times, [-n(:,2), n(:,1)], sd(:,2)./sqrt(sum(n.^2, 2)));
            
            if nargin < 3
                doPlot = false;
            end
            if doPlot
                plot(obj, 'DisplayName','SplinePath');
                hold on
                [xb,yb] = obj.eval(obj.Breaks);
                plot(xb, yb, 'b', 'LineStyle','none','Marker','.', 'MarkerSize',15, 'DisplayName','Breaks');
                plot(xy(:,1), xy(:,2), 'o', 'DisplayName','xy');
                plot(Q(:,1), Q(:,2), 'kx', 'DisplayName','Q');
                hold off
                legend('-DynamicLegend')
            end%if
            
        end%fcn
        
        function s = cumlengths(obj, idx0, idx1)
            s = obj.ArcLengths;
        end%fcn
        
        function [xy,tau,errFlag] = intersectLine(obj, O, psi, doPlot)
            
            obj1 = obj.shift(-O).rotate(-psi);
            
            breaks = obj1.Breaks;
            coefsY = permute(obj1.Coefs(2,:,:), [2 3 1]);
            
            % There are at most Nc-1 real roots (i.e. solutions) per piece
            [Ns,Nc] = size(coefsY);
            coder.varsize('tau', Ns*(Nc-1));
            tau = zeros(0,1);
            
            % The first pieces except the last are defined over half open
            % intervals [b0,b1)
            b0 = breaks(1);
            for i = 1:obj1.numel()-1
                b1 = breaks(i+1);
                ri = realroots(coefsY(i,:));
                isValid = (0 <= ri) & (ri < b1-b0);
                tau = [tau; ri(isValid) + b0]; %#ok<AGROW>
                b0 = b1;
            end%for
            
            % The last piece is defined over the closed interval [b0,b1]
            b1 = breaks(end);
            ri = realroots(coefsY(end,:));
            isValid = (0 <= ri) & (ri <= b1-b0);
            tau = [tau; ri(isValid) + b0];
            
            tau = sort(tau, 'ascend');
            errFlag = isempty(tau);
            [x,y] = obj.eval(tau);
            xy = [x,y];
            
            if (nargin > 3) && doPlot
                [~,ax] = plot(obj);
                hold on
                
                [r1,r2] = scaleTangentToAxis(xlim, ylim, O, psi);
                Pstart  = [O(1) + r2*cos(psi); O(2) + r2*sin(psi)];
                Pstop   = [O(1) + r1*cos(psi); O(2) + r1*sin(psi)];
                plot(gca, [Pstart(1) Pstop(1)], [Pstart(2) Pstop(2)], ...
                    'Displayname','Line')
                
                plot(ax, xy(:,1), xy(:,2), 'ko')
                hold off
            end%if
            
        end%fcn
        
        function [xy,tau,errFlag] = intersectCircle(obj, C, r)
            error('Not implemented!')
        end%fcn
        
        function flag = isempty(obj)
            flag = (obj.numel() < 1);
        end%fcn
        
        function s = length(obj, tau)
            
            if nargin < 2
                s = obj.ArcLengths(end);
            else
                idx = find(tau > obj.Breaks, 1, 'last');
                taus = linspace(obj.Breaks(idx), tau, 100);
                xy = diff(ppval(obj.mkpp(), taus), 1, 2);
                s = obj.ArcLengths(idx) + hypot(xy(1,:), xy(2,:));
            end%if
            
        end%fcn
        
        function pp = mkpp(obj)
        %MKPP   Create piecewise polynomial struct.
        %   PP = MKPP(OBJ) creates piecewise polynomial structure PP from
        %   path OBJ.
        %
        %   See also PPVAL, MKPP, UNMKPP.
        
            assert(~obj.isempty(), 'Path must be non-empty!')
            pp = mkpp(obj.Breaks, obj.Coefs, 2);
        end%fcn
        
        function [Q,idx,tau,fval] = pointProjection(obj, poi, ~, doPlot)
            
            Px = poi(1);
            Py = poi(2);
            breaks = obj.Breaks;
            coefsX = permute(obj.Coefs(1,:,:), [2 3 1]);
            coefsY = permute(obj.Coefs(2,:,:), [2 3 1]);
            [Ns,Nc] = size(coefsX);
            
            % There are at most 2Nc-2 solutions per piece
            coder.varsize('tau', Ns*(2*Nc-2));
            coder.varsize('idx', Ns*(2*Nc-2));
            tau = zeros(0,1);
            idx = zeros(0,1);
            b0 = breaks(1);
            for i = 1:obj.numel()
                b1 = breaks(i+1);
                px = coefsX(i,:);
                py = coefsY(i,:);
                dpx = polyDiff(px);
                dpy = polyDiff(py);
                
                % Convolution returns array of size 2N-2. Therefore, pad
                % non-convolutional term with zeros.
                convTerm = conv2(px,dpx) + conv2(py,dpy);
                ri = realroots([zeros(1,Nc-1), Px*dpx + Py*dpy] - convTerm);
                isValid = (0 <= ri) & (ri <= b1 - b0);
                taui = sort(ri(isValid), 'ascend');
                tau = [tau; b0 + taui]; %#ok<AGROW>
                idx = [idx; repmat(i, size(taui))]; %#ok<AGROW>
                
                b0 = b1;
            end%for
            Q = ppval(obj.mkpp(), tau)';
            fval = zeros(size(tau));
            
            if (nargin > 3) && doPlot
                plot(obj, 'DisplayName','RefPath');
                hold on
                [x0,y0] = obj.eval(obj.Breaks);
                plot(x0, y0, 'g.', 'MarkerSize',12, 'DisplayName','Breaks');
                plot(poi(1), poi(2), 'ro', 'DisplayName','PoI')
                plot(Q(:,1), Q(:,2), 'kx', 'DisplayName','Q')
                legend('-DynamicLegend', 'Location','best');
                plot(...
                    [Q(:,1)'; repmat([poi(1) NaN], size(Q,1),1)'],...
                    [Q(:,2)'; repmat([poi(2) NaN], size(Q,1),1)'], 'k:'); 
                hold off
            end%if
            
        end%fcn
        
        function n = numel(obj)
            n = size(obj.Coefs, 2); % Return number of spline segments
        end%fcn
        
        function obj = restrict(obj, tau0, tauF)
            
            assert(tau0 < tauF)
            
            % Find the lower/upper index so that restricted domain is
            % covered
            [tauL,tauU] = obj.domain();
            taus = obj.Breaks;
            if isempty(tau0) || (tau0 < tauL)
                idx0 = 1;
            else
                idx0 = find(tau0 >= taus, 1, 'last');
            end
            if isempty(tauF) || (tauF > tauU)
                idxF = obj.numel();
            else
                idxF = find(tauF >= taus, 1, 'last');
            end%if
            
            obj = obj.select(idx0:idxF);
            obj.Breaks(1) = tau0;
            obj.Breaks(end) = tauF;
            
        end%fcn
        
        function obj = reverse(obj)
            error('Not implemented!')
        end%fcn
        
        function obj = rotate(obj, phi)
            
            narginchk(1, 2);
            
            if nargin < 2
                tau0 = obj.domain();
                [~,~,~,phi] = obj.eval(tau0);
                phi = -phi;
            end%if
            
            R = rotmat2D(phi);
            for i = 1:builtin('numel', obj)
                coefs = obj(i).Coefs;
                for ii = 1:obj.numel() % Loop over segments
                   coefs(:,ii,:) = R*permute(coefs(:,ii,:), [1 3 2]);
                end
                obj(i).Coefs = coefs;
            end%for
            
        end%fcn
        
        function obj = select(obj, idxs)
            
            idxsc = idxs(:);
            tmp = unique([idxsc, idxsc+1]);
            s = obj.ArcLengths(tmp);
            obj = SplinePath(obj.Breaks(tmp), obj.Coefs(:,idxs,:), s - s(1));
            
        end%fcn
        
        function obj = shift(obj, P)
            
            % Handle input arguments
            narginchk(1, 2);
            
            if nargin < 2
                P = -obj(1).termPoints();
            end%if
            
            if numel(P) ~= 2 || ~isnumeric(P)
                error(['Method SHIFTBY requires a numeric input',...
                    ' argument with two elements.']);
            end%if
            
            % BUILTIN is supported for code-generation starting with R2017b
            for i = 1:builtin('numel', obj) 
                obj(i).Coefs(:,:,end) = bsxfun(@plus, obj(i).Coefs(:,:,end), P(:));
            end%for
            
        end%fcn
        
        function [P0,P1] = termPoints(obj)
            
            [tau0,tau1] = obj.domain();
            [x,y] = obj.eval([tau0,tau1]);
            P0 = [x(1); y(1)];
            P1 = [x(2); y(2)];
            
        end%fcn
        
        function s = toStruct(obj)
            s = struct(...
                'breaks',obj.Breaks', ...
                'coefs',obj.Coefs, ...
                'lengths',obj.ArcLengths);
        end%fcn
        
    end%methods
    
    
    methods (Access = private)
        
        function s = lengthIdxTau(obj, idx, tau)
            tau0 = obj.Breaks(idx)';
            assert(all(tau0 < tau));
            
            s = obj.ArcLengths(idx);
            for i = 1:numel(tau)
                taui = linspace(tau0(i), tau(i), 100);
                xy = diff(ppval(obj.mkpp(), taui), 1, 2);
                s(i) = s(i) + sum(hypot(xy(1,:), xy(2,:)));
            end
        end%fcn
        
    end%methods
    
    
    methods (Static)
        
        function obj = ll2Path(lat, lon) %#ok<STOUT,INUSD>
            error('Not implemented!')
        end%fcn
        
        function obj = pp2Path(pp)
            [breaks,coefs,nbrSeg,polyOrd,dim] = unmkpp(pp);
            assert(dim == 2)
            obj = SplinePath(breaks, reshape(coefs, 2, nbrSeg, polyOrd));
        end%fcn
        
        function obj = xy2Path(x, y) %#ok<STOUT,INUSD>
            error('Not implemented!')
        end%fcn
        
        function obj = fromStruct(s)
            obj = SplinePath(s.breaks, s.coefs, s.lengths);
        end%fcn
        
        function c = getBusDef()
            BusName = 'SBus_SplinePath';
            HeaderFile = '';
            Description = '';
            BusElements = {...
                {'breaks',      101, 'double', -1, 'real', 'Sample', 'Variable', [], [], '', ''},...
                {'coefs', [2,100,4], 'double', -1, 'real', 'Sample', 'Variable', [], [], '', ''},...
                {'lengths',     101, 'double', -1, 'real', 'Sample', 'Variable', [], [], '', ''},...
                };
            c = {{BusName,HeaderFile,Description,BusElements}};
        end%fcn
        
    end%methods
    
end%class
