\m5_TLV_version 1d: tl-x.org
\SV
/*
Copyright (c) 2018, Steven F. Hoover

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The name of Steven F. Hoover
      may not be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

\m5
 nullify(
  // ====================
  // Generic Logic Macros
  // ====================

  // Expand to a concatination.
  // Big endian concatinates {[0], [1], ...}
  // Little endian concatinates {..., [1], [0]}
  // Generally, little endian is unnecessary, as [*] references do the same thing, but we've come across tools that
  // can't handle the multiple packed dimensions [*] creates.
  // Params:
  //   $1: Scope.
  //   $2: The number of indices in the scope [n-1:0].
  //   $3: Signal to concatinate inside scope.
  m4_define(['m4_hier_concat_big_endian'],
            ['{m4_forloop(['m4_ind'], 0, $2, ['m4_ifelse(m4_ind, 0, [''], [', '])$1[m4_ind]$2'])}'])
  m4_define(['m4_hier_concat_little_endian'],
            ['{m4_forloop(['m4_ind'], 0, $2, ['m4_ifelse(m4_ind, 0, [''], [', '])$1[m4_eval($2 - m4_ind - 1)]$2'])}'])


  // ##################################
  // Single-line verif macros
  // (multi-line versions later)

  // ==========
  // Assertions
  // ==========

  // A shorthand for a concurrent assertion statement (which, of course can infer staging logic).
  m4_define(['m4_assert'], ['assert property (@(posedge *clk) *reset || ($1)) else \$error($2);'])


  // ========
  // Printing
  // ========
  // One-line versions of the corresponding multiline macros:
  m4_define(['m4_display'], ['always_ff @(posedge clk) \$display($1);'])
  m4_define(['m4_display_if'], ['always_ff @(posedge clk) if ($1) \$display($2);'])

  // For \TLV tree_redux:
  m4_define(['m4_tree_redux_uniquifier'], 0)
 )


// This can be used to instantiate an m4_ macro (with any number of argumenets) that produces no new lines
// using a multi-line instantiation.
\TLV instantiate(_macro_name, _etc)
   m4_echo(['m4_']['_macro_name'])(m4_shift($@))
\TLV with(_etc)
   m4_push(tmp, m4_push_TLV_set(, $@))
   m5+m4_tmp
   m4_pop_set()m4_pop(tmp)
\TLV with_seq(_etc)
   m4_push(tmp, m4_push_TLV_set(_seq, $@))
   m5+m4_tmp
   m4_pop_set()m4_pop(tmp)
\TLV ifelse(_a, _b, _match_block, _mismatch_block, _etc)
   m4_ifelse(['_a'], ['_b'], ['m5+_match_block'], m4_eval($# == 4), 1, ['m5+_mismatch_block'], m4_eval($# > 4), 1, ['m4_push(_ifelse_args, ['m4_shift(m4_shift(m4_shift($@)))'])m5+ifelse(m4__ifelse_args)m4_pop(_ifelse_args)'], [''])


// forloop(_var, #from, #to, _block)
// Repeat a block of TLV code.
//   _var: Loop variable (m4 macro, prepended with "m4_")
//   #from: Initial (low) value of ['m4_']_var.
//   #to: Non-inclusive high value of ['m4_']_var.
//   _block: The TLV code block to repeat.
\TLV forloop(_var, #_from, #_to, _block)
   m4_push(['_var'], ['#_from'])// forloop(_var, #_from, #_to, <block>)
   m5+forloop_inner(['_var'], ['#_from'], ['#_to'], ['_block'])
   m4_pop(['_var'])
\TLV forloop_inner(_var, #_from, #_to, _block)
   // forloop_inner(_var, #_from, #_to, <block>)
   m5+ifelse(m4_eval(#_from < #_to), 0, [''],
      \TLV
         m5+_block
         m4_push(['_var'], m4_eval(m4_echo(['m4_']_var) + 1))
         m5+forloop_inner(['_var'], m4_eval(#_from + 1), ['#_to'], ['_block'])
         m4_pop(['_var'])
      )

// Apply an operation across a hierarchy in a tree.
// /_hier[*]@_stage$_sig is reduced by applying _op in a tree, to produce @_stage$_sig.
// The tree of redux logic can be distributed over pipeline stages.
// Each level of reduction is provided its own hierarchy level instance to replicate the reduction,
// with a lower index of 0. Each level fans in by exactly that level's _branching_factor, until the spread is enough
// to cover #_MIN..#_MAX. If the spread, at this final (input) level exceeds #_MAX, a _default_value is used.
// Many parameters can use $1, etc. substitutions. These must be passed in using m4_arg(n).
// Params:
//   /_source_hier: The hierarchy level to which to apply the operation.
//   #_MAX, #_MIN: Max/min (inclusive) range of hierarchy to reduce.
//   @_stage: The stage at which to apply the operation, where $1 is the level number.
//   $_sig: The signal resulting from the operation, including its range, where $1 is substituted for the level number.
//   _branching_factor: _branching_factor-to-1 reduction into each level, where $1 is the level number. 
//   _op: The operation to apply, where $1 and $2 represent the input $_sigs, eg ['$1 + $2'], where $3 is the level number.
//   _default_value: The value/expression to reduce at the last level beyond #_MAX.
// Example:
//   m5+tree_redux(/top, /flat, 9, 0, @1, $sig[3:0], 3, m4_arg(1) + m4_arg(2), [''0'])
\TLV tree_redux(/_top, /_source_hier, #_MAX, #_MIN, @_stage, $_sig, _branching_factor, _op, _default_value)
   m5+with(
      top,         ['/_top'],
      max,         ['#_MAX'],
      min,         ['#_MIN'],
      stage,       ['m4_strip_prefix(@_stage)'],
      sig,         ['m4_strip_prefix($_sig)'],
      branching_factor, ['_branching_factor'],
      op,          ['_op'],
      source_hier_name, m4_strip_prefix(/_source_hier),
      source_hier_cnt,  m4_eval(#_MAX - #_MIN + 1),
      ['# Base name of intermediate-level hierarchies, given $1 = level.'],
      base_hier_name, ['m4_source_hier_name['_tree']m4_tree_redux_uniquifier['_level']'],
      level, 0,
      \TLV
         m5+tree_redux_inner(0, 1)
         @m4_stage
            $m4_sig = /m4_base_hier_name['0'][0]$m4_sig;  // Pull $_sig out of level0 hierarchy scope.
      )
   m4_def(tree_redux_uniquifier, m4_eval(m4_tree_redux_uniquifier + 1))

// For use by tree_redux only, using macros defined by \TLV tree_redux.
// Params:
//   #_level: 0.., logic level of the reduduction.
//   #_spread: 1, m4_branching_factor(0), , the number of outputs to reduce at this level.
\TLV tree_redux_inner(#_level, #_spread)
   m5+with_seq(
      level,        ['#_level'],
      next_level,   ['m4_eval(#_level + 1)'],
      in_spread,    ['m4_eval(#_spread * m4_branching_factor(#_level))'],
      last_level,   ['m4_eval(m4_in_spread >= m4_source_hier_cnt)'],
      level_has_leftover_terms, ['m4_eval(m4_in_spread > m4_source_hier_cnt)'],
      level_min,    ['m4_ifexpr(m4_last_level, m4_min, 0)'],
      ['# Macro providing the name of a hierarchy level, given $1 = level.'],
      in_hier_scope, ['m4_top/m4_ifexpr(m4_last_level, ['m4_source_hier_name'], ['m4_base_hier_name['']m4_next_level'])'],
      fanin,        ['m4_ifexpr(m4_last_level, m4_hier_cnt, m4_in_spread)'],
      ['# TLV expression for the next-level hier index for the first fanin signal.'],
      base_index_expr, ['#m4_base_hier_name['']#_level * m4_branching_factor(#_level) + m4_level_min'],
      \TLV
         // Recursively generate upstream logic.
         m4_ifexpr(m4_last_level, [''], ['m5+tree_redux_inner(m4_next_level, m4_in_spread)'])
         // Logic at this level.
         /m4_base_hier_name['']#_level[m4_eval(m4_min + #_spread - 1):m4_min]
            @m4_stage
               m5+with(
                  ['# Define op_expr as a recursive macro returning the single-line redux expression, either a signal or the operation on the
                    # signal and the remaining operations.
                    # op_expr(cnt)'],
                  op_expr,
                  ['m4_with(
                     op1, ['m4_in_hier_scope[m4_base_index_expr + m4_cnt]m4_with(level, m4_next_level, ['$m4_sig'])'],
                     op2, ['m4_ifexpr(m4_cnt < m4_branching_factor(#_level) - 2,
                                      ['(m4_with(cnt, m4_eval(m4_cnt + 1), ['m4_op_expr['']']))'],
                                      ['m4_in_hier_scope[m4_base_index_expr + m4_eval(m4_cnt + 1)]m4_with(level, m4_next_level, ['$m4_sig'])'])'],
                     ['m4_op['']'])'],
                  \TLV
                     $m4_sig = m4_with(cnt, 0, ['m4_op_expr']);
                  )
      )

// Reduction macro.
// Performs an operation across all instances of a hierarchy and provides the result outside that hierarchy.
// m5+redux($sum[7:0], /hier, max, min, $addend, '0, +)
\TLV redux($_redux_sig,/_hier,#_MAX,#_MIN,$_sig,$_init_expr ,_op)
   \always_comb
      $['']$_redux_sig = $_init_expr ;
      for (int i = #_MIN; i <= #_MAX; i++)
         $_redux_sig = $_redux_sig _op /_hier[i]$_sig;


// Similar to m5+redux, but each element is conditioned.
// Performs an operation across all instances of a hierarchy and provides the result outside that hierarchy.
// m5+redux_cond($selected_value[7:0], /hier, max, min, $value, '0, |, $select)
\TLV redux_cond($_redux_sig,/_hier,#_MAX,#_MIN,$_sig,$_init_expr ,_op,$_cond_expr)
   /_hier[*]
      $_sig['']_cond = $_cond_expr ? $_sig : $_init_expr ;
   \always_comb
      $['']$_redux_sig = $_init_expr ;
      for (int i = #_MIN; i <= #_MAX; i++)
         $_redux_sig = $_redux_sig _op /_hier[i]$_sig;


// Select across a hierarchy (MUX) with a decoded select.  Works for $pipe_signals and $ANY.
// m5+select($selected_value[7:0], /top, /hier, ...fix)
//$_redux_sig The resulting signal, including bit range.
//  /_top Base scope for references.
// /_hier  use /_top['']/_hier[*]/_subhier
// /_subhier Replicated logic is created under m4_hier[*].
//m4_pushdef(['m4_MAX'],          ['$8'])
//m4_pushdef(['m4_MIN'],          ['$9'])
// /_sel_sig_subhier /_top['']/_hier[*]$_sel_sig_subhier['']$_sel_sig selects an input.
// $_redux_sig_cond    When condition for redux sig.  [''] for none (produces '0 if no select);  ['-'] or ['-$signame'] to generate as "| /_top['']/_hier[*]/_sel_sig_subhier['']/_sel_sig"; ['$signame'] to use given signal.
\TLV select($_redux_sig, /_top, /_hier, /_subhier, /_sel_sig_subhier, $_sel_sig, $_sig, $_redux_sig_cond)
   
   m4_pushdef(['m4_hier_index'], ['m4_substr(/_hier, 1)'])
   m4_pushdef(['m4_assign_redux_sig_cond'], m4_ifelse(m4_substr(m4_redux_sig_cond, 0, 1), ['-'], ['true'], ['']))  // Has '-'.
   m4_pushdef(['S_redux_sig_cond'],         m4_ifelse(m4_substr($_redux_sig_cond, 0, 1), ['-'], m4_substr($_redux_sig_cond, 1), $_redux_sig_cond))  // Remove '-'.
   m4_define(['S_redux_sig_cond'],         m4_ifelse(S_redux_sig_cond, [''], $_sel_sig['']_cond, S_redux_sig_cond))  // Make up a signal name if not provided.
   
   // This is a suboptimal implementation for simulation.
   // It does AND/OR reduction.  It would be better in simulation to simply index the desired value,
   //   but this is not currently supported in SandPiper as it is not legal across generate loops.
   /_hier[*]
      /accum
         \always_comb
            if (m4_hier_index == \$low(/_top['']/_hier[*]/_sel_sig_subhier['']$_sel_sig))
               $['']$_sig = /_top['']/_hier/_sel_sig_subhier['']$_sel_sig ? /_top['']/_hier['']/_subhier['']$_sig : '0;
            else
               $_sig = /_top['']/_hier['']/_sel_sig_subhier['']$_sel_sig ? /_top['']/_hier['']/_subhier$_sig : /_hier[m4_hier_index-1]/accum$_sig;
   m4_ifelse($_redux_sig_cond,['-'], m4_pragma_disable_quote_checks['
   $_redux_sig = /_hier[\$high(/_top['']/_hier[*]/_sel_sig_subhier['']$_sel_sig)]/accum$_sig;
   '], ['
   m4_ifelse(m4_assign_redux_sig_cond, [''], [''], S_redux_sig_cond = | m/_top/_hier[*]/_sel_sig_subhier['']$_sel_sig;)
   m4_ifelse(S_redux_sig_cond, [''], [''], ?S_redux_sig_cond)
   m4_ifelse(S_redux_sig_cond, [''], [''], ['   '])$_redux_sig = /_hier[\$high(/_top['']/_hier[*]/_sel_sig_subhier['']$_sel_sig)]/accum$_sig;'])
   /* Old way:m4_pragma_enable_quote_checks
   \always_comb
      $m4_redux_sig = m4_init;
      for (int i = m4_MIN; i <= m4_MAX; i++)
         m4_redux_sig = m4_redux_sig | (m4_hier[i]m4_index_sig['']_match ? m4_hier[i]m4_sig : '0);
   */

   m4_popdef(['S_redux_sig_cond'])
   m4_popdef(['m4_hier_index'])
   m4_popdef(['m4_assign_redux_sig_cond'])




// ================================================================================
// A TL-Verilog M4 library of macros for verification, logging, and instrumentation
// ================================================================================
// (Similar to verif.vh, but as M4 macros.)


// ##################################
// Multi-line macros


// ========
// Printing
// ========

// A macro for printing every clk cycle.
// Params:
//   args: The arguments for the \$display call (the print string and variables).
\TLV display(args)
   \SV_plus
      always_ff @(posedge clk) \$display(args);

// A macro for printing under a condition.
// Params:
//   $cond: The condition under which to display (often the signal of the associated $when condition).
//   args: The arguments for the \$display call (the print string and variables).
\TLV display_if($cond, args)
   \SV_plus
      always_ff @(posedge clk) begin
         if ($cond) \$display(args);
      end
