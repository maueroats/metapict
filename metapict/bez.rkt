#lang racket
;;; Bezier Curves

; A Bezier curve is represented as
;     (struct bez (p0 p1 p2 p3) #:transparent)
; Our curves will be represented 

(provide bez~             ; compare two Bezier curves, precision optional
         control-points   ; Construct the bez from p0 to p3 that leaves p0 in direction w0
         ;                ; and arrives in p3 in the direction w3 with tensions t0 and t3 respectively
         bez/dirs+tensions 
         bez->dc-path     ; convert a bez to a dc-path
         bezs->dc-path    ; convert a list of bezs to a single dc-path         
         draw-bez         ; draw a bez on a dc with optional transformation and pen-transformation
         draw-bezs        ; same but draws a list of bezs
         bez-intersection-times  ; return times t1 and t2 s.t. γ1(t1)=γ2(t2)
         bez-intersection-point  ; return intersection point of two Bezier curves
         bez-intersection-point-and-times
         (contract-out
          [bez-reverse  (-> bez?              bez?)] ; reverse orientation
          [point-of-bez (-> bez? real?        pt?)]  ; find the point γ(t)
          [bez-subpath  (-> bez? real? real?  bez?)] ; subpath from and to the given times
          [split-bez    (-> bez? real?        (values bez? bez?))]  ; Split bez at time t
          ; [bez-large-bounding-box (-> bez? window?)] ; bounding box (maybe larger than curve)
          ))

(require racket/draw pict
         "angles.rkt"
         "pen-and-brush.rkt"
         "dc.rkt"
         "def.rkt"         
         "pt-vec.rkt"
         "mat.rkt"         
         "trans.rkt"
         "trig.rkt"
         "structs.rkt"
         "window.rkt")

; point-of-bez : bez number -> pt
(define (point-of-bez b t)
  ; b determines a Bezier curve γ. Return γ(t).
  (defm (bez p0 p1 p2 p3) b)
  (define (g ps) ; de Casteljau's algorithm
    (match (length ps)
      [0 (pt 0 0)]
      [1 (first ps)]
      [2 (med t (first ps) (second ps))]
      [_ (med t (g (drop-right ps 1)) (g (rest ps)))]))
  (g (list p0 p1 p2 p3)))

(module+ test (require rackunit)
  (def a-bez (bez (pt 0 1) (pt 2 3) (pt 4 5) (pt 6 7)))
  (check-equal? (point-of-bez a-bez 0) (pt 0 1))
  (check-equal? (point-of-bez a-bez 1) (pt 6 7))
  (def a-bez2 (bez (pt 0 0) (pt 1 1) (pt 1 1) (pt 2 0)))
  (check-equal? (point-of-bez a-bez2 1/2) (pt 1 3/4)))

; split-bez : bez number -> (values bez bez)
(define (split-bez b t)
  ; Given a Bezier curve b from p0 to p3 with control
  ; points p1 and p2, split the Bezier curve at time t 
  ; in two parts b1 (from p0 to b(t)) and b2 (from b(t) to p3),
  ; such that (point-of-bez b1 1) = (point-of-bez b2 0)
  ; and the graphs of b1 and b2 gives the graph of b.
  (defm (bez p0 p1 p2 p3) b)  
  (def q0 (med t p0 p1))
  (def q1 (med t p1 p2))
  (def q2 (med t p2 p3))
  (def r0 (med t q0 q1))
  (def r1 (med t q1 q2))
  (def s  (med t r0 r1))
  (values (bez p0 q0 r0 s)
          (bez s r1 q2 p3)))

(module+ test
  (require "def.rkt")
  (defv (b1 b2) (split-bez a-bez 1/3))
  (defm (bez a b c d) b1)
  (defm (bez e f g h) b2)
  (defm (bez i j k l) a-bez)
  (check-equal? (list a d h) (list i e l))
  (check-equal? d (point-of-bez a-bez 1/3)))

; bez-reverse : bez -> bez
;   reverse the direction of the Bezier curve
(define (bez-reverse b)
  (defm (bez p0 p1 p2 p3) b)
  (bez p3 p2 p1 p0))

(module+ test
  (check-equal? (point-of-bez (bez-reverse a-bez) 1/3)
                (point-of-bez a-bez 2/3)))

; bez-subpath : bez real real -> bez
;   given a Bezier curve b return a new Bezier curve c, 
;   such that c(0)=b(t0) and c(1)=b(t1) and
;   the graph of c is a subset of the graph of b.
(define (bez-subpath b t0 t1)
  (cond
    [(> t0 t1)  (bez-subpath (bez-reverse b) t1 t0)]
    [(< t0 0)   (bez-subpath b 0 (max t1 0))]
    [(> t1 1)   (bez-subpath b (min t0 1) 1)]
    [(= t0 t1)  (def p (point-of-bez b t0))
                (bez p p p p)]                
    [else ; 0<=t0<t1<=1
     (defv (b0 b1) (split-bez b t0))
     (defv (b2 b3) (split-bez b1 (/ (- t1 t0) (- 1 t0))))
     b2]))

(module+ test (require "def.rkt")
  (let () ; case t0<t1 
    (def sub (bez-subpath a-bez 1/3 2/3))
    (check-equal? (point-of-bez sub 0) (point-of-bez a-bez 1/3))
    (check-equal? (point-of-bez sub 1) (point-of-bez a-bez 2/3)))
  (let () ; case t0<0 
    (def sub (bez-subpath a-bez -1/3 2/3))
    (check-equal? (point-of-bez sub 0) (point-of-bez a-bez 0))
    (check-equal? (point-of-bez sub 1) (point-of-bez a-bez 2/3)))
  (let () ; case t1>1 
    (def sub (bez-subpath a-bez 1/3 4/3))
    (check-equal? (point-of-bez sub 0) (point-of-bez a-bez 1/3))
    (check-equal? (point-of-bez sub 1) (point-of-bez a-bez 1)))
  (let () ; case t0>t1
    (def sub (bez-subpath a-bez 2/3 1/3))
    (check-equal? (point-of-bez sub 0) (point-of-bez a-bez 2/3))
    (check-equal? (point-of-bez sub 1) (point-of-bez a-bez 1/3))))

; bez~ : bez bez [positive-real] -> boolean
;   compare whether the defining points of the two Bezier curves
;   are within a distance of ε. The value of 0.0001 was chosen
;   to mimick the precision of MetaPost.
(define (bez~ b1 b2 [ε 0.0001]) ; MetaPost precision isn't that great
  (defm (bez a b c d) b1)
  (defm (bez e f g h) b2)
  (define (close? x y) (<= (dist x y) ε))
  (andmap values (map close? (list a b c d) (list e f g h))))

(module+ test
  (check-true (bez~ a-bez a-bez))
  (check-false (bez~ a-bez (bez-subpath a-bez 0 0.9)))
  (check-true (bez~ a-bez (bez-subpath a-bez 0 0.9) 10)))

; bez-large-bounding-box : bez -> window
;  return a large (approximate) bounding box that
;  includes all defining points.
(define (bez-large-bounding-box b)
  (defm (bez (pt x0 y0) (pt x1 y1) (pt x2 y2) (pt x3 y3)) b)
  (def xmin (min x0 x1 x2 x3))
  (def ymin (min y0 y1 y2 y3))
  (def xmax (max x0 x1 x2 x3))
  (def ymax (max y0 y1 y2 y3))
  (window xmin xmax ymin ymax))

(module+ test
  (for ([t (in-range 0 1 1/10)])
    (check-true (pt-in-window? (point-of-bez a-bez 0) (bez-large-bounding-box a-bez)))))


; bez->dc-path : bez [transform or #f] -> dc-path
;   Convert the Bezier curve into a dc-path.
;   If the transform is present, then use it on the curve first.
(define (bez->dc-path b [t #f])
  (bezs->dc-path (list b) t))

; todo: implement dc-path=?
; (module+ test (check-equal? (bez->dc-path a-bez) (bezs->dc-path (list a-bez))))

; bezs->dc-path : list-of-bez [transform or #f] -> dc-path
;   Convert the list of "consecutive" Bezier curves into a dc-path.
;   If the transform is present, then use it on the curve first.
(define (bezs->dc-path bs [t #f]) ; assumes the bez ends and start points match
  (def (T b) (if t (t b) b)) ; transform points if t is present
  (def p (new dc-path%))
  (defm (list b0 b. ...) bs) 
  (defm (bez (pt x0 y0) (pt x1 y1) (pt x2 y2) (pt x3 y3)) (T b0))
  (send p move-to x0 y0)
  (send p curve-to x1 y1 x2 y2 x3 y3)
  (for ([b b.])
    (defm (bez (pt x0 y0) (pt x1 y1) (pt x2 y2) (pt x3 y3)) (T b))
    (send p curve-to x1 y1 x2 y2 x3 y3))
  p)

; draw-bezs : dc% list-of-bez [#:transformation trans] [#:pen-transformation trans] -> 
(define (draw-bezs dc bs #:transformation [t #f] #:pen-transformation [pent #f])
  (def ob (send dc get-brush))
  (send dc set-brush "white" 'transparent) ; prevents filling of path
  (def T (or t identity))
  (def P (or pent identity))
  (def ot (send dc get-transformation))
  (set-transformation dc (T P))
  (send dc draw-path (bezs->dc-path bs (inverse P)))
  (send dc set-brush ob)
  (send dc set-transformation ot))

(define (draw-bez dc b #:transformation [t #f] #:pen-transformation [pent #f])
  (draw-bezs dc (list b) #:transformation t #:pen-transformation pent))

; control-points : pt pt real real real real -> (values pt pt)
(define (control-points p0 p3 θ φ τ0 τ3)
  ; Construct the Bezier curve from p0 to p3 that leaves p0 in direction w0
  ; and arrives in p3 in the direction w3 with tensions t0 and t3 respectively.
  ; TODO: Minimum tension of 3/4 ?
  (def a (sqrt 2))
  (def b 1/16)
  (def c (/ (- 3 (sqrt 5)) 2))
  (def (f θ φ) ; (131)
    (defv (cosθ sinθ) (cos&sin θ))
    (defv (cosφ sinφ) (cos&sin φ))
    (def α (* a (- sinθ (* b sinφ)) (- sinφ (* b sinθ)) (- cosθ cosφ)))
    (/ (+ 2 α) (* 3  (+ 1  (* (- 1 c) cosθ)  (* c cosφ)))))
  (def v (pt- p3 p0))
  (def p1 (pt+ p0 (vec* (/ (f θ φ) τ0) (rot/rad θ     v))))
  (def p2 (pt- p3 (vec* (/ (f φ θ) τ3) (rot/rad (- φ) v))))
  (values p1 p2))

; bez/dirs+tensions : pt pt vec vec [real] [real] -> bez
(define (bez/dirs+tensions p0 p3 w0 w3 [τ0 1] [τ3 1])
  (def v (pt- p3 p0))
  (def θ (angle2 w0 v))
  (def φ (angle2 w3 v))
  (defv (p1 p2) (control-points p0 p3 θ φ τ0 τ3))
  (bez p0 p1 p2 p3))

; bez-intersection-point : bez bez -> pt-or-#f
(define (bez-intersection-point b1 b2)
  (def ptu (bez-intersection-point-and-times b1 b2))
  (and ptu (first ptu)))

(module+ test
  (defv (bez3 bez4) (values (bez (pt 0. 0.) (pt 0 0) (pt 2 2) (pt 2 2)) 
                            (bez (pt 0 2)   (pt 0 2) (pt 2 0) (pt 2 0))))
  (check-true (pt~ (bez-intersection-point bez3 bez4) (pt 1 1))))

; bez-intersection-times : bez bez -> (values real real)
(define (bez-intersection-times b1 b2)
  (def ptu (bez-intersection-point-and-times b1 b2))
  (and ptu (let () (defm (list _ t u) ptu)
             (values t u))))

(module+ test  
  (let () (defv (t1 t2) (bez-intersection-times bez3 bez4))
    (check-true (pt~ (pt t1 t2) (pt 1/2 1/2)))))

(define (bez-intersection-point-and-times b1 b2 [t- 0] [t+ 1] [u- 0] [u+ 1])
  (set! t- (* 1. t-))
  (set! t+ (* 1. t+))
  (set! u- (* 1. u-))
  (set! u+ (* 1. u+))  
  ; (display (list (abs (- t+ t-)) (abs (- u+ u-)) t+ u+))
  ; (display " ")
  ; (displayln (list b1 b2 t- t+ u- u+))
  ; return either #f or (list p t u), where p = b1(t) = b2(u)
  (def again bez-intersection-point-and-times)
  (def ε 1e-15) ; precision
  (define (very-small? w)
    (defm (window x- x+ y- y+) w)
    (and (<= (- x+ x-) ε) 
         (<= (- y+ y-) ε)))
  (def (mid s t) (/ (+ s t) 2))
  (def bb1 (bez-large-bounding-box b1))
  (def bb2 (bez-large-bounding-box b2))
  (and (or (= t+ t-) (= u+ u-) ; todo: why are these checks needed?
           (window-overlap? bb1 bb2))
       (or (and (very-small? bb1) (very-small? bb2)
                (list (window-center bb1) ; point
                      ; todo : instead of the center, find 
                      ; the intersection of lines
                      (/ (+ t- t+) 2)     ; time on original b1
                      (/ (+ u- u+) 2)))   ; time on original b2
           (let ()
             (defv (b11 b12) (split-bez b1 1/2))
             (defv (b21 b22) (split-bez b2 1/2))
             (or (again b11 b21 t- (mid t- t+) u- (mid u- u+))
                 (again b11 b22 t- (mid t- t+) (mid u- u+) u+)
                 (again b12 b21 (mid t- t+) t+ u- (mid u- u+))
                 (again b12 b22 (mid t- t+) t+ (mid u- u+) u+))))))

(define (bezier b) ; bez -> pict
  (def dc-path (bez->dc-path b))
  (defv (left top lw lh) (send dc-path get-bounding-box)) ; user space
  (defv (width height) (values (+ left lw) (+ top lh)))
  ; (displayln (list left top lw lh width height))
  (dc (λ (dc dx dy) 
        (let ([ob (send dc get-brush)])
          (send dc set-brush (find-white-transparent-brush))
          (send dc draw-path dc-path dx dy)
          (send dc set-brush ob)))
      width height))