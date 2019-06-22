#!/bin/bash
###################################################################
# Nome : backup_mysql_<versao>.sh
# Autor: Helio Faria
# Data: 06-04-2019
# Versao: 1.1
# Revisao:1
###################################################################
# Programa para executar backup diario das bases do MySQL deste servidor.
# Faz autenticacao com usuario Backup.
# Armazena os Logs de cada execucao em /var/log/backup.
# Os backups sao armazenados em $DIR_BACKUP.
# Cada base de dados tem seu proprio diretorio de backup e serao geradas sub-pastas com as datas dos backups.
# Os 15 ultimos backups ficarao armazenados e sao rotacionados apagando sempre o backup mais antigo.
# Todos os arquivos serao compactados.
####################################################################
# Changelog 
# - 08042019 - Adicionado o parametro do tempo de execucao total de todo o backup entre a execucao de cada funcao.
# - 09042019 - Modificado usuario de backup.
#
#
#

# Changelog 


##### Variaveis do BACKUP
export MYSQL_PWD="###########"
MYSQLUSER="backup"
MYSQLDUMP=/usr/bin/mysqldump
MYSQL=/usr/bin/mysql

##### Variaveis de sistema e LOG
DIR_LOG=/var/log/backup
LOG_INFO=/var/log/backup/bkp_info.log
DATA=`date +%d%m%Y_%H%M`
DIR_BACKUP="/var/backup/mysql"

##### Variaveis de alerta do Zabbix
IP="192.168.0.176"
HOST_FRONT="ss-intranet"
ITEMKEY="bkp.mysql.status"
ITEMKEYERRO="bkp.mysql.status.erro"
ITEMBANCOERRO="bkp.mysql.conect"
SUCESSO="OK"
FUNCIONANDO="Nenhum Erro"
ERROBASES="erro.acesso.no.banco"
ERROPASSO1="erro.criacao.arquivo"
ERROPASSO2="erro.compactacao"
ERROPASSO3="erro.rotacao"


###################################################################
# Verificando as bases de dados
###################################################################

$MYSQL -u $MYSQLUSER -e "SHOW DATABASES;" | grep -Ev "(information_schema|performance_schema|mysql|Database)" 2>> $LOG_INFO 
		if [ "$?" -eq 0 ]; then
			echo "$DATA: Acesso ao banco de dados está ok!" >> $LOG_INFO
			echo "$DATA: Acesso ao banco de dados está ok!"
    			zabbix_sender -z $IP -s $HOST_FRONT -k $ITEMBANCOERRO -o $SUCESSO
		else
    			zabbix_sender -z $IP -s $HOST_FRONT -k $ITEMBANCOERRO -o $ERROBASES
     			echo "ERRO ao acessar o banco." 
     			echo "ERRO ao acessar o banco." >> $LOG_INFO 
			exit 0
   		fi


DATABASES=$($MYSQL -u $MYSQLUSER -e "SHOW DATABASES;" | grep -Ev "(information_schema|performance_schema|mysql|Database)")

###################################################################
# Verificando existência do diretório de LOG
##################################################################

if [ -e $DIR_LOG ]; then
   echo "Diretório de Log já existe: $DATA"
   echo "Diretorio de log já existe: $DATA" >> $LOG_INFO
else
   mkdir -p $DIR_LOG 
   echo "Diretorio criado com sucesso: $DATA"
   echo "Diretorio criado com sucesso: $DATA" >> $LOG_INFO
   continue
fi

###################################################################
# Verificando existência do diretório de Backup
##################################################################

if [ -e $DIR_BACKUP ]; then
   echo "Diretório de Backup já existe: [$DIR_BACKUP]: $DATA."
   echo "Diretório de Backup já existe: [$DIR_BACKUP]: $DATA." >> $LOG_INFO
else
   mkdir -p $DIR_BACKUP 
   echo "Diretorio criado com sucesso: [$DIR_BACKUP]: $DATA"
   echo "Diretorio criado com sucesso: [$DIR_BACKUP]: $DATA" >> $LOG
   continue
fi
echo "Iniciando backup do banco de dados"

##################################################################
# Função que executa o backup
##################################################################

###################################################################
#PASSO01: EXECUTANDO BACKUP DO BANCO 
###################################################################

executa_Backup(){
echo "Inicio do backup: $DATA" 
echo "Inicio do backup: $DATA" >> $LOG_INFO
declare CONT=0

#inicia o laço de execução dos backups 
for banco in $DATABASES
do
	if [ $CONT -ge 0 ]; then  
		NOME=backup_"$DATA"_"$banco".sql
		DATA_BKPDIR=`mkdir -p $DIR_BACKUP/$banco/$DATA`

	echo "Iniciando backup do banco de dados [$banco]"
	echo "Iniciando backup do banco de dados [$banco]: $DATA" >> $DIR_LOG/bkp_$banco".log"
	$MYSQLDUMP -u $MYSQLUSER --single-transaction --databases $banco > $DIR_BACKUP/$banco/$DATA/$NOME

######### verifica se o comando foi bem sucedido ou nao.
		if [ "$?" -eq 0 ]; then
			echo "$DATA: Backup Banco de dados [$banco] completo." 
			echo "$DATA: Backup Banco de dados [$banco] completo." >> $DIR_LOG/bkp_$banco".log"
		else
    			zabbix_sender -z $IP -s $HOST_FRONT -k $ITEMKEYERRO -o $ERROPASSO1
     			echo "ERRO ao realizar o Backup do Banco de dados [$banco]: $DATA" 
     			echo "ERRO ao realizar o Backup do Banco de dados [$banco]: $DATA" >> $DIR_LOG/bkp_$banco"_error".log
			exit 0
   		fi
	fi
CONT=`expr $CONT + 1`
done
}

##################################################################
# Função que COMPACTA O BACKUP
##################################################################

####################################################################
#PASSO02: COMPACTANDO O BANCO
####################################################################

compacta_Backup (){
echo "Compactando os arquivos de backup: $DATA"
echo "Compactando os arquivos de backup: $DATA" >> $LOG_INFO
declare CONT=0

#inicia o laço de execução da compactação dos backups

for banco in $DATABASES
do
	if [ $CONT -ge 0 ]; then
		NOME=backup_"$DATA"_"$banco".sql
		bzip2 $DIR_BACKUP/$banco/$DATA/$NOME 2> /dev/null

#########verifica se o backup foi compactado
			if [ "$?" -eq 0 ]; then
               			echo "$DATA: Backup do Banco de dados [$banco] foi compactado com sucesso." 
               			echo "$DATA: Backup do Banco de dados [$banco] foi compactado com sucesso." >> $DIR_LOG/bkp_$banco".log"
        		else    
				zabbix_sender -z $IP -s $HOST_FRONT -k $ITEMKEYERRO -o $ERROPASSO2
                		echo "ERRO na compactacao do backup do [$banco]: $DATA" 
                		echo "ERRO na compactacao do backup do [$banco]: $DATA" >> $DIR_LOG/bkp_$banco"_error".log
				exit 0
        		fi
	fi
CONT=`expr $CONT + 1`
done
}

#####################################################################
# Função que executa ROTAÇÃO DOS BACKUPS
#####################################################################

#####################################################################
# ROTACIONANDO OS BACKUPS - Remove Backups mais antigos 10 dias
#####################################################################

rotaciona_Backup (){
echo "Removendo Backups Antigos: $DATA"
echo "Removendo Backups Antigos: $DATA" >> "$LOG_INFO"
declare CONT=0

#inicia o laço de verificação de backups antigos

for banco in $DATABASES
do
	numero=`ls $DIR_BACKUP/$banco/ | wc -w`
	echo "Número de backups da base de dados do banco $banco é $numero"
	if [ $numero -gt 15  ] ; then
		ls -td1 $DIR_BACKUP/$banco/* | sed -e '1,15d' |xargs -d '\n' rm -rf --verbose >> $DIR_LOG/bkp_$banco".log"
		numero_atual=`ls $DIR_BACKUP/$banco/ | wc -w`
   		echo "Backup Local rotacionado com sucesso, Total $numero_atual"
    		echo "Backup Local rotacionado com sucesso, Total $numero_atual: $DATA" >> $DIR_LOG/bkp_$banco".log"
	     else if [ $numero -lt 15 ]; then
    		echo "Número de backups é inferior ao estipulado para ser mantido: $numero_atual"
    		echo "Número de backups é inferior ao estipulado para ser mantido: $numero_atual" >> $DIR_LOG/bkp_$banco".log"
   	     fi
	fi
CONT=`expr $CONT + 1`
done
}


#####################################################################
#EXECUTA FUNÇÕES
#####################################################################
t_Inicial=$(date +%s)
executa_Backup 
#sleep 10
compacta_Backup
#sleep 10
rotaciona_Backup
data_Atual=$(date +%d+%M+%Y)
t_Final=$(expr `date +%s` - $t_Inicial)
echo "Final do backup: $data_ATUAL" >> $LOG_INFO
echo " Tempo total da execução do backup foi de $t_Final"s"" >>$LOG_INFO
echo "##################################################################" >> $LOG_INFO
