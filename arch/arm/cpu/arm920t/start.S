
#include <common.h>
#include <config.h>



.globl _start
_start:	b	start_code
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
	ldr	pc, _not_used
	ldr	pc, _irq
	ldr	pc, _fiq

_undefined_instruction:	.word undefined_instruction
_software_interrupt:	.word software_interrupt
_prefetch_abort:	.word prefetch_abort
_data_abort:		.word data_abort
_not_used:		.word not_used
_irq:			.word irq
_fiq:			.word fiq

	.balignl 16,0xdeadbeef



_TEXT_BASE:
	.word	TEXT_BASE

.globl _armboot_start
_armboot_start:
	.word _start

/*
 * These are defined in the board-specific linker script.
 */
.globl _bss_start
_bss_start:
	.word __bss_start

.globl _bss_end
_bss_end:
	.word _end

#ifdef CONFIG_USE_IRQ
/* IRQ stack memory (calculated at run-time) */
.globl IRQ_STACK_START
IRQ_STACK_START:
	.word	0x0badc0de

/* IRQ stack memory (calculated at run-time) */
.globl FIQ_STACK_START
FIQ_STACK_START:
	.word 0x0badc0de
#endif


/*
 * the actual start code
 */

start_code:
	/*
	 * set the cpu to SVC32 mode
	 */
	mrs	r0, cpsr
	bic	r0, r0, #0x1f
	orr	r0, r0, #0xd3
	msr	cpsr, r0

#define pWTCON	0x53000000
#define INTMSK	0x4A000008	/* Interupt-Controller base addresses */
#define INTSUBMSK	0x4A00001C
#define CLKDIVN	0x4C000014	/* clock divisor register */

#define INTSUBMSK_val	0xffff
#define MPLLCON_val	((0x7f << 12) + (0x2 << 4) + 0x1)	/* 405.00 MHz */
#define UPLLCON_val	((0x38 << 12) + (0x2 << 4) + 0x2)
#define CLKDIVN_val	5 /* FCLK:HCLK:PCLK = 1:3:6 */
	/* turn off the watchdog */

	ldr	r0, =pWTCON
	mov	r1, #0x0
	str	r1, [r0]

	/*
	 * mask all IRQs by setting all bits in the INTMR - default
	 */
	mov	r1, #0xffffffff
	ldr	r0, =INTMSK
	str	r1, [r0]

	ldr	r1, =INTSUBMSK_val
	ldr	r0, =INTSUBMSK
	str	r1, [r0]


	/* Clock asynchronous mode */
	mrc	p15, 0, r1, c1, c0, 0
	orr	r1, r1, #0xc0000000
	mcr	p15, 0, r1, c1, c0, 0


#define LOCKTIME	0x4c000000
#define UPLLCON		0x4c000008

	ldr	r0, =LOCKTIME
	mov	r1, #0xffffff
	str	r1, [r0]

	ldr	r0, =UPLLCON
	ldr	r1, =UPLLCON_val
	str	r1, [r0]
	
	/* Page 7-19, seven nops between UPLL and MPLL */
	nop
	nop
	nop
	nop
	nop
	nop
	nop

	ldr	r1, =MPLLCON_val
	str	r1, [r0, #-4]		/* MPLLCON */

	/* FCLK:HCLK:PCLK = 1:2:4 */
	/* default FCLK is 120 MHz ! */
	ldr	r0, =CLKDIVN
	mov	r1, #CLKDIVN_val
	str	r1, [r0]
	/*
	 * we do sys-critical inits only at reboot,
	 * not when booting from ram!
	 */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
# ifndef CONFIG_LL_INIT_NAND_ONLY
	bl	cpu_init_crit
# endif
#endif

#ifndef CONFIG_SKIP_RELOCATE_UBOOT
	adr	r0, _start		/* r0 <- current position of code   */
relocate:				/* relocate U-Boot to RAM	    */
	ldr	r1, _TEXT_BASE		/* test if we run from flash or RAM */
	cmp	r0, r1			/* don't reloc during debug         */
	beq	done_relocate	

	ldr	r2, _armboot_start
	ldr	r3, _bss_start
	sub	r2, r3, r2		/* r2 <- size of armboot            */
	add	r2, r0, r2		/* r2 <- source end address         */

copy_loop:
	ldmia	r0!, {r3-r10}		/* copy from source address [r0]    */
	stmia	r1!, {r3-r10}		/* copy to   target address [r1]    */
	cmp	r0, r2			/* until source end addreee [r2]    */
	ble	copy_loop

	mov	r0, #0			/* flush v3/v4 cache	*/
	mcr	p15, 0, r0, c7, c7, 0
	ldr	pc, _done_relocate	/* jump to relocated code	    */
_done_relocate:
	.word	done_relocate
done_relocate:

#endif	/* CONFIG_SKIP_RELOCATE_UBOOT */

	/* Set up the stack						    */
stack_setup:
	ldr	r0, _TEXT_BASE		/* upper 128 KiB: relocated uboot   */
	sub	r0, r0, #CONFIG_SYS_MALLOC_LEN	/* malloc area              */
	sub	r0, r0, #CONFIG_SYS_GBL_DATA_SIZE /* bdinfo                 */
#ifdef CONFIG_USE_IRQ
	sub	r0, r0, #(CONFIG_STACKSIZE_IRQ+CONFIG_STACKSIZE_FIQ)
#endif
	sub	sp, r0, #12		/* leave 3 words for abort-stack    */
	bic	sp, sp, #7		/* 8-byte alignment for ABI compliance */

clear_bss:
	ldr	r0, _bss_start		/* find start of bss segment        */
	ldr	r1, _bss_end		/* stop here                        */
	mov	r2, #0x00000000		/* clear                            */

clbss_l:str	r2, [r0]		/* clear loop...                    */
	add	r0, r0, #4
	cmp	r0, r1
	ble	clbss_l

	ldr	pc, _start_armboot

_start_armboot:	.word start_armboot


/*
 *************************************************************************
 *
 * CPU_init_critical registers
 *
 * setup important registers
 * setup memory timing
 *
 *************************************************************************
 */


#ifndef CONFIG_SKIP_LOWLEVEL_INIT
cpu_init_crit:
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
	orr	r0, r0, #0x00000002	@ set bit 2 (A) Align
	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-Cache
	mcr	p15, 0, r0, c1, c0, 0

	/*
	 * before relocating, we have to setup RAM timing
	 * because memory timing is board-dependend, you will
	 * find a lowlevel_init.S in your board directory.
	 */
	mov	ip, lr

	bl	lowlevel_init

	mov	lr, ip
	mov	pc, lr
#endif /* CONFIG_SKIP_LOWLEVEL_INIT */

/*
 *************************************************************************
 *
 * Interrupt handling
 *
 *************************************************************************
 */

@
@ IRQ stack frame.
@
#define S_FRAME_SIZE	72

#define S_OLD_R0	68
#define S_PSR		64
#define S_PC		60
#define S_LR		56
#define S_SP		52

#define S_IP		48
#define S_FP		44
#define S_R10		40
#define S_R9		36
#define S_R8		32
#define S_R7		28
#define S_R6		24
#define S_R5		20
#define S_R4		16
#define S_R3		12
#define S_R2		8
#define S_R1		4
#define S_R0		0

#define MODE_SVC	0x13
#define I_BIT		0x80

/*
 * use bad_save_user_regs for abort/prefetch/undef/swi ...
 * use irq_save_user_regs / irq_restore_user_regs for IRQ/FIQ handling
 */

	.macro	bad_save_user_regs
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}			@ Calling r0-r12
	ldr	r2, _armboot_start
	sub	r2, r2, #(CONFIG_STACKSIZE)
	sub	r2, r2, #(CONFIG_SYS_MALLOC_LEN)
	/* set base 2 words into abort stack */
	sub	r2, r2, #(CONFIG_SYS_GBL_DATA_SIZE+8)
	ldmia	r2, {r2 - r3}			@ get pc, cpsr
	add	r0, sp, #S_FRAME_SIZE		@ restore sp_SVC

	add	r5, sp, #S_SP
	mov	r1, lr
	stmia	r5, {r0 - r3}			@ save sp_SVC, lr_SVC, pc, cpsr
	mov	r0, sp
	.endm

	.macro	irq_save_user_regs
	sub	sp, sp, #S_FRAME_SIZE
	stmia	sp, {r0 - r12}			@ Calling r0-r12
	add	r7, sp, #S_PC
	stmdb	r7, {sp, lr}^			@ Calling SP, LR
	str	lr, [r7, #0]			@ Save calling PC
	mrs	r6, spsr
	str	r6, [r7, #4]			@ Save CPSR
	str	r0, [r7, #8]			@ Save OLD_R0
	mov	r0, sp
	.endm

	.macro	irq_restore_user_regs
	ldmia	sp, {r0 - lr}^			@ Calling r0 - lr
	mov	r0, r0
	ldr	lr, [sp, #S_PC]			@ Get PC
	add	sp, sp, #S_FRAME_SIZE
	/* return & move spsr_svc into cpsr */
	subs	pc, lr, #4
	.endm

	.macro get_bad_stack
	ldr	r13, _armboot_start		@ setup our mode stack
	sub	r13, r13, #(CONFIG_STACKSIZE)
	sub	r13, r13, #(CONFIG_SYS_MALLOC_LEN)
	/* reserve a couple spots in abort stack */
	sub	r13, r13, #(CONFIG_SYS_GBL_DATA_SIZE+8)

	str	lr, [r13]			@ save caller lr / spsr
	mrs	lr, spsr
	str	lr, [r13, #4]

	mov	r13, #MODE_SVC			@ prepare SVC-Mode
	@ msr	spsr_c, r13
	msr	spsr, r13
	mov	lr, pc
	movs	pc, lr
	.endm

	.macro get_irq_stack			@ setup IRQ stack
	ldr	sp, IRQ_STACK_START
	.endm

	.macro get_fiq_stack			@ setup FIQ stack
	ldr	sp, FIQ_STACK_START
	.endm

/*
 * exception handlers
 */
	.align  5
undefined_instruction:
	get_bad_stack
	bad_save_user_regs
	bl	do_undefined_instruction

	.align	5
software_interrupt:
	get_bad_stack
	bad_save_user_regs
	bl	do_software_interrupt

	.align	5
prefetch_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_prefetch_abort

	.align	5
data_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_data_abort

	.align	5
not_used:
	get_bad_stack
	bad_save_user_regs
	bl	do_not_used

#ifdef CONFIG_USE_IRQ

	.align	5
irq:
	get_irq_stack
	irq_save_user_regs
	bl	do_irq
	irq_restore_user_regs

	.align	5
fiq:
	get_fiq_stack
	/* someone ought to write a more effiction fiq_save_user_regs */
	irq_save_user_regs
	bl	do_fiq
	irq_restore_user_regs

#else

	.align	5
irq:
	get_bad_stack
	bad_save_user_regs
	bl	do_irq

	.align	5
fiq:
	get_bad_stack
	bad_save_user_regs
	bl	do_fiq

#endif
