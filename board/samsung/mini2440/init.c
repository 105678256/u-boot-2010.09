#define NFCONF (*((volatile unsigned long *)0x4E000000))
#define NFCONT (*((volatile unsigned long *)0x4E000004))
#define NFCMMD (*((volatile unsigned char *)0x4E000008))
#define NFADDR (*((volatile unsigned char *)0x4E00000C))
#define NFDATA (*((volatile unsigned char *)0x4E000010))
#define NFSTAT (*((volatile unsigned char *)0x4E000020))
/* GPIO */
#define GPHCON              (*(volatile unsigned long *)0x56000070)
#define GPHUP               (*(volatile unsigned long *)0x56000078)
void copy_to_sdram(unsigned char *src, unsigned char *dest, unsigned int size)
{	
	nand_read((unsigned char)*src, *dest, size);	}

#define BUSY 1
	inline void wait_idle(void) {
		int i;

		while(!(NFSTAT & BUSY))
			for(i=0; i<10; i++);
	}

#define NAND_SECTOR_SIZE	512
#define NAND_BLOCK_MASK		(NAND_SECTOR_SIZE - 1)
int nand_read(unsigned char *buf, unsigned long start_addr, unsigned int size)
{	int i, j;
	if ((start_addr & NAND_BLOCK_MASK) || (size & NAND_BLOCK_MASK)) {
		return -1;	}
	NFCONF = (3<<8);
	NFCONT = (1<<0);
	for(i=0; i<10; i++);

	for(i=start_addr; i < (start_addr + size);)
	{	NFSTAT |= (1<<2);

		NFCMMD = 0;
		NFADDR = i & 0xff;
		NFADDR = (i >> 9) & 0xff;
		NFADDR = (i >> 17) & 0xff;
		NFADDR = (i >> 25) & 0xff;

		wait_idle();

		for(j=0; j < NAND_SECTOR_SIZE; j++, i++) {
			*buf = (NFDATA & 0xff);
			buf++;
		}
	}
	NFCONT |= 0x02;	
	return 0;	}

