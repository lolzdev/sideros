(module $core.wasm
  (type (;0;) (func (param i32) (result i64)))
  (func $preinit (type 0) (param i32) (result i64)
    (local i32 i32 i64 i64 i64)
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          local.get 0
          i32.const 2
          i32.lt_u
          br_if 0 (;@3;)
          local.get 0
          i32.const -1
          i32.add
          local.tee 1
          i32.const 7
          i32.and
          local.set 2
          local.get 0
          i32.const -2
          i32.add
          i32.const 7
          i32.ge_u
          br_if 1 (;@2;)
          i64.const 1
          local.set 3
          i64.const 0
          local.set 4
          br 2 (;@1;)
        end
        local.get 0
        i64.extend_i32_u
        return
      end
      local.get 1
      i32.const -8
      i32.and
      local.set 0
      i64.const 1
      local.set 3
      i64.const 0
      local.set 4
      loop  ;; label = @2
        local.get 3
        local.get 4
        i64.add
        local.tee 4
        local.get 3
        i64.add
        local.tee 3
        local.get 4
        i64.add
        local.tee 4
        local.get 3
        i64.add
        local.tee 3
        local.get 4
        i64.add
        local.tee 4
        local.get 3
        i64.add
        local.tee 3
        local.get 4
        i64.add
        local.tee 4
        local.get 3
        i64.add
        local.set 3
        local.get 0
        i32.const -8
        i32.add
        local.tee 0
        br_if 0 (;@2;)
      end
    end
    block  ;; label = @1
      local.get 2
      i32.eqz
      br_if 0 (;@1;)
      local.get 3
      local.set 5
      loop  ;; label = @2
        local.get 5
        local.get 4
        i64.add
        local.set 3
        local.get 5
        local.set 4
        local.get 3
        local.set 5
        local.get 2
        i32.const -1
        i32.add
        local.tee 2
        br_if 0 (;@2;)
      end
    end
    local.get 3)
  (memory (;0;) 16)
  (global $__stack_pointer (mut i32) (i32.const 1048576))
  (export "memory" (memory 0))
  (export "preinit" (func $preinit)))
