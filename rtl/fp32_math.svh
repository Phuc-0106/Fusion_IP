// fp32_math.svh — IEEE-754 single-precision math (simulation-oriented)
//
// Include only when +define+USE_FP32 is set at compile time.
// Uses SystemVerilog shortreal conversion — suitable for Questa/ModelSim
// functional simulation; not a synthesizable FP32 ALU for generic ASIC.
//
`ifndef FP32_MATH_SVH
`define FP32_MATH_SVH

function automatic logic signed [31:0] fp_mul;
    input logic signed [31:0] a, b;
    shortreal ra, rb;
    begin
        ra     = $bitstoshortreal(a);
        rb     = $bitstoshortreal(b);
        fp_mul = $shortrealtobits(ra * rb);
    end
endfunction

function automatic logic signed [31:0] fp_add;
    input logic signed [31:0] a, b;
    begin
        fp_add = $shortrealtobits($bitstoshortreal(a) + $bitstoshortreal(b));
    end
endfunction

function automatic logic signed [31:0] fp_sub;
    input logic signed [31:0] a, b;
    begin
        fp_sub = $shortrealtobits($bitstoshortreal(a) - $bitstoshortreal(b));
    end
endfunction

function automatic logic signed [31:0] fp_recip;
    input logic signed [31:0] d;
    shortreal rd, abs_rd;
    begin
        rd     = $bitstoshortreal(d);
        abs_rd = (rd < 0.0) ? -rd : rd;
        if (abs_rd < 1.0e-30)
            fp_recip = `FP_MAX;
        else
            fp_recip = $shortrealtobits(1.0 / rd);
    end
endfunction

// Cholesky / general √v  (v as float bits)
function automatic logic signed [31:0] fp_sqrt_nr;
    input logic signed [31:0] v;
    shortreal rv;
    begin
        rv = $bitstoshortreal(v);
        if (rv <= 0.0)
            fp_sqrt_nr = 32'h0;
        else
            fp_sqrt_nr = $shortrealtobits($sqrt(rv));
    end
endfunction

function automatic bit fp32_le_zero;
    input logic signed [31:0] x;
    begin
        fp32_le_zero = ($bitstoshortreal(x) <= 0.0);
    end
endfunction

function automatic logic signed [31:0] fp_neg;
    input logic signed [31:0] x;
    begin
        fp_neg = $shortrealtobits(-$bitstoshortreal(x));
    end
endfunction

function automatic bit fp_abs_gt_eps;
    input logic signed [31:0] a;
    input logic signed [31:0] eps_bits;
    shortreal aa, ee;
    begin
        aa = $bitstoshortreal(a);
        ee = $bitstoshortreal(eps_bits);
        fp_abs_gt_eps = (aa > ee) || (aa < -ee);
    end
endfunction

// Wrap heading ψ to (−π, π] — matches ukf_predictor norm_angle (UKF covariance / mean).
function automatic logic signed [31:0] fp_norm_angle_bits;
    input logic signed [31:0] angle_bits;
    shortreal a;
    begin
        a                = $bitstoshortreal(angle_bits);
        fp_norm_angle_bits = $shortrealtobits($atan2($sin(a), $cos(a)));
    end
endfunction

`endif // FP32_MATH_SVH
