# Sistema Penitenciário — Banco de Dados PostgreSQL



Banco de dados relacional completo desenvolvido em \*\*PostgreSQL\*\* para o gerenciamento operacional de uma unidade prisional. Projeto acadêmico da disciplina de Banco de Dados.



\## Sobre o Projeto



O sistema controla toda a operação de uma unidade prisional: funcionários, cargos, departamentos, celas, detentos, controle de acessos e auditoria automática. Desenvolvimento realizado de forma majoritariamente individual.



O banco segue \*\*normalização completa (3FN)\*\*, com \*\*7 tabelas\*\*, \*\*89 registros reais\*\*, \*\*9 chaves estrangeiras\*\* e diversos recursos avançados de automação e segurança.



\## Tecnologias e Recursos



\- \*\*Banco de Dados:\*\* PostgreSQL

\- \*\*Linguagem:\*\* PL/pgSQL

\- \*\*Schema dedicado:\*\* `prisional`

\- \*\*Recursos:\*\* Triggers, Procedures, Functions, JSONB, Índices B-tree, Roles com permissões granulares



\## Estrutura de Tabelas



| Tabela             | Descrição                                                    |

| ------------------ | ------------------------------------------------------------ |

| `cargo`            | Hierarquia de cargos com níveis (1-5) e indicação de chefia  |

| `departamento`     | 5 departamentos com chefe vinculado                          |

| `funcionario`      | 18 funcionários com CPF, matrícula, turno e status           |

| `cela`             | 15 celas com capacidade, ocupação, nível de segurança e tipo |

| `detento`          | 23 detentos com regime, periculosidade e vínculo com cela    |

| `acesso`           | Registro de acessos de funcionários às celas                 |

| `auditoria\_acesso` | Log automático de todas as alterações em acessos             |



\## Recursos Avançados



\### Função — `fn\_verificar\_permissao\_acesso`



Verifica se um funcionário tem permissão para acessar determinada cela, validando status, nível de cargo, tipo de cela e regras específicas para enfermaria, segurança máxima e isolamento.



\### Procedure — `sp\_registrar\_movimentacao\_detento`



Centraliza todas as movimentações de detentos (transferência, liberação, isolamento, internação, retorno). Executa validações de permissão, verifica lotação, atualiza status e registra o acesso automaticamente.



\### Triggers (2)



\- \*\*`trg\_validar\_lotacao\_cela`\*\* — Atualiza automaticamente a ocupação das celas e impede lotação excedida.

\- \*\*`trg\_auditoria\_acesso`\*\* — Registra automaticamente quem alterou, quando e os dados antigos/novos em formato JSONB.



\### Índices



7 índices B-tree estratégicos para performance em consultas reais.



\### Segurança



4 roles com permissões granulares (acesso completo para desenvolvedores, acesso restrito para avaliador).



\## Regras de Negócio



\- Constraints CHECK em praticamente todas as colunas (turno, status, periculosidade, datas, ocupação)

\- Integridade referencial completa com 9 chaves estrangeiras

\- Impossível inserir dados inválidos — tudo validado por constraints, triggers e procedures



\## Como Executar



1\. Instale o PostgreSQL

2\. Execute o script de criação do banco (`CREATE SCHEMA prisional`)

3\. Execute o dump completo fornecido

4\. Todas as tabelas, dados, funções, triggers e permissões serão criados automaticamente



\## Autor



\*\*Guilherme Holanda\*\* — Estudante de Engenharia de Software

